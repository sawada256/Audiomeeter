import Foundation
import CoreAudio
import AudioToolbox
import Accelerate
import VMNative

/// Immutable insert-chain snapshot read by the render callback (read-copy-update).
/// The UI thread publishes a new snapshot and releases the old one only after the
/// callback has moved past it, so chains change without stopping device IO.
final class InsertChainSnapshot {
    struct Slot {
        let insert: HostedInsert
        let position: InsertPosition
        let sidechain: StripID?
        let sidechainBus: BusID?
    }
    let chains: [[Slot]] // Indexed by graph node.
    let byTarget: [InsertTarget: [HostedInsert]]
    init(_ inserts: [InsertTarget: [HostedInsert]]) {
        byTarget = inserts.filter { !$0.value.isEmpty }
        var chains = [[Slot]](repeating: [], count: MixerTopology.nodes)
        for (target, slots) in byTarget {
            chains[SidechainRenderGraph.node(target)] = slots.map {
                Slot(insert: $0, position: $0.config.position, sidechain: $0.config.sidechain, sidechainBus: $0.config.sidechainBus)
            }
        }
        self.chains = chains
    }
}

/// Audiomeeter Master Audio Engine coordinating the routing matrix and DSP
public final class AudiomeeterEngine {
    public static let shared = AudiomeeterEngine()

    public private(set) var engineSampleRate: Double = 48000.0
    public private(set) var bufferSize: UInt32 = 256
    public private(set) var isRunning: Bool = false
    public private(set) var deviceErrors: [String] = []

    private let allStrips = StripID.allCases
    private let allBuses = BusID.allCases
    private let allInsertTargets = InsertTarget.all

    // Input Strips State & Workers
    private var inputIOs: [StripID: AudioInputIO] = [:]
    private var inputRingBuffers: [StripID: StereoRingBuffer] = [:]
    private var stripDSPs: [StripID: StripDSP] = [:]
    private var stripMeters: [StripID: MeterLevel] = [:]
    // Audio-thread-owned copies. The callback must never wait for the UI lock.
    private var realtimeStripMeters: [StripID: MeterLevel] = [:]
    private var stripDevices: [StripID: AudioDeviceInfo] = [:]
    private var busDevices: [BusID: AudioDeviceInfo] = [:]
    // Devices identical to the A1 master are served inside the master IOProc:
    // no second IOProc, ring, priming delay or drift resampling. Changed with IO stopped.
    private var directInputs = [Bool](repeating: false, count: MixerTopology.strips)
    private var directOutputs = [Bool](repeating: false, count: MixerTopology.buses)

    // Output Buses State & Workers
    private var dawEndpoints: [StripID: AudioDeviceID] = [:]
    private var dawOutputs: [BusID: AudioOutputIO] = [:]
    private let dawRings: [BusID: StereoRingBuffer] = [
        .B1: StereoRingBuffer(capacityFrames: 16384),
        .B2: StereoRingBuffer(capacityFrames: 16384)
    ]
    private func dawBus(for strip: StripID) -> BusID? {
        switch strip { case .virtualVAIO: return .B1; case .virtualAUX: return .B2; default: return nil }
    }
    private var masterDeviceID: AudioObjectID?
    private var masterIOProcID: AudioDeviceIOProcID?
    private var outputIOs: [BusID: AudioOutputIO] = [:]
    private var outputRingBuffers: [BusID: StereoRingBuffer] = [:]
    private var busDSPs: [BusID: BusDSP] = [:]
    private var busMeters: [BusID: MeterLevel] = [:]
    private var realtimeBusMeters: [BusID: MeterLevel] = [:]
    public weak var recorderPlayer: AudioRecorderPlayer?

    let spectrumCapture = SpectrumCapture()

    // Runtime switches are atomics, so changing them never stops device IO.
    private let optionFlags = vm_counter_create()!
    private enum Option: UInt64 { case latencyCompensation = 1, outputBusAlignment = 2, sidechainAlignment = 4 }
    private func option(_ option: Option) -> Bool { vm_counter_load(optionFlags) & option.rawValue != 0 }
    private func setOption(_ option: Option, _ value: Bool) {
        let flags = vm_counter_load(optionFlags)
        vm_counter_store(optionFlags, value ? flags | option.rawValue : flags & ~option.rawValue)
    }
    var latencyCompensationEnabled: Bool { get { option(.latencyCompensation) } set { setOption(.latencyCompensation, newValue) } }
    var outputBusAlignmentEnabled: Bool { get { option(.outputBusAlignment) } set { setOption(.outputBusAlignment, newValue) } }
    var sidechainAlignmentEnabled: Bool { get { option(.sidechainAlignment) } set { setOption(.sidechainAlignment, newValue) } }
    private let packedBusOrder = vm_counter_create()!
    var busProcessingOrder: [BusProcessingStage] {
        get { (0..<5).map { BusProcessingStage.unpacked(vm_counter_load(packedBusOrder), at: $0) } }
        set { if BusProcessingStage.isValid(newValue) { vm_counter_store(packedBusOrder, BusProcessingStage.packed(newValue)) } }
    }

    // Insert chains (RCU). `inserts` is the main-thread view; setting it publishes.
    private let chainPointer = vm_counter_create()!
    private var currentChains = InsertChainSnapshot([:])
    private var retiredChains: [(snapshot: InsertChainSnapshot, beat: UInt64)] = []
    var inserts: [InsertTarget: [HostedInsert]] {
        get { currentChains.byTarget }
        set { publishInserts(newValue) }
    }
    private func publishInserts(_ value: [InsertTarget: [HostedInsert]]) {
        let next = InsertChainSnapshot(value)
        retiredChains.append((currentChains, vm_counter_load(heartbeat)))
        currentChains = next
        vm_counter_store(chainPointer, UInt64(UInt(bitPattern: Unmanaged.passUnretained(next).toOpaque())))
        reclaimRetiredChains()
    }
    /// Releases chain snapshots the callback can no longer hold. Call from the main thread.
    func reclaimRetiredChains() {
        guard !retiredChains.isEmpty else { return }
        let beat = vm_counter_load(heartbeat)
        // A cycle that loaded an old pointer has finished once a later cycle started.
        retiredChains.removeAll { !isRunning || beat >= $0.beat + 2 }
    }
    /// Swaps one hosted insert for another (worker restart) without stopping audio.
    func replaceInsert(_ old: HostedInsert, with new: HostedInsert) {
        var value = inserts
        for (target, slots) in value {
            if let index = slots.firstIndex(where: { $0 === old }) { value[target]![index] = new }
        }
        inserts = value
    }

    // Whole-chain ON/OFF is an atomic node mask, so toggling it never stops device IO.
    private let disabledInsertMask = vm_counter_create()!
    private var cycleDisabledMask: UInt64 = 0 // Loaded once per render cycle.
    var disabledInsertTargets: Set<InsertTarget> {
        get { Set(allInsertTargets.filter { vm_counter_load(disabledInsertMask) & Self.maskBit($0) != 0 }) }
        set { vm_counter_store(disabledInsertMask, newValue.reduce(0) { $0 | Self.maskBit($1) }) }
    }
    private static func maskBit(_ target: InsertTarget) -> UInt64 { 1 << UInt64(SidechainRenderGraph.node(target)) }
    private let heartbeat = vm_counter_create()!
    public var renderHeartbeat: UInt64 { vm_counter_load(heartbeat) }
    private var renderSequence: UInt64 = 0
    // Diagnostics written by the render callback (single writer), read by the UI.
    private let cycleNanos = vm_counter_create()!
    private let cycleMaxNanos = vm_counter_create()!
    private let cycleOverruns = vm_counter_create()!
    private var timebase = mach_timebase_info_data_t()
    private var busTaps: [BusID: UnsafeMutablePointer<Float>] = [:]
    private var busTapFrames = 0
    private var feedbackBusTaps: [BusID: UnsafeMutablePointer<Float>] = [:]
    private var currentPans: [StripID: Float] = [:]
    private func internalBus(_ uid: String?) -> BusID? {
        DedicatedDevice.returnBus(uid)
    }
    private var stripTaps: [StripID: UnsafeMutablePointer<Float>] = [:]
    private var stripHistories: [StripID: StereoSampleHistory] = [:]
    // A strip writes its delay history only while some route reads it with a delay.
    private var stripNeedsHistory = [Bool](repeating: false, count: MixerTopology.strips)
    private var busDelays: [BusID: StereoDelayLine] = [:]
    private var busOutputDelays: [BusID: StereoDelayLine] = [:]
    private var playbackDelays: [BusID: StereoDelayLine] = [:]
    private let routeScratch = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
    private var graphRouting = [UInt16](repeating: 0, count: MixerTopology.nodes)
    private var graphSidechains = [UInt16](repeating: 0, count: MixerTopology.nodes)
    private var renderGraph = SidechainRenderGraph(routingEdges: [], sidechainEdges: [])
    private var nodeLatencies = [Int](repeating: 0, count: MixerTopology.nodes)
    private var busManualLatencies = [Int](repeating: 0, count: MixerTopology.buses)
    // Indexed by graph node. Element-wise publication keeps both arrays uniquely
    // owned, so the render callback never triggers a copy-on-write allocation.
    private var realtimeCompensation = [Int](repeating: 0, count: MixerTopology.nodes)
    private var publishedCompensation = [Int](repeating: 0, count: MixerTopology.nodes)
    private var publishedNodeLatencies = [Int](repeating: 0, count: MixerTopology.nodes)
    func insertLatency(_ target: InsertTarget) -> Int {
        vm_counter_load(disabledInsertMask) & Self.maskBit(target) != 0 ? 0 : (inserts[target] ?? []).reduce(0) { $0 + ($1.fullyBypassed ? 0 : $1.latency) }
    }
    private func processInserts(_ chains: InsertChainSnapshot, target: InsertTarget, position: InsertPosition, buffer: UnsafeMutablePointer<Float>, upstream: Int, frames: Int, alignSidechains: Bool) -> Int {
        let node = SidechainRenderGraph.node(target)
        guard cycleDisabledMask & Self.maskBit(target) == 0 else {
            for slot in chains.chains[node] where slot.position == position { slot.insert.markIdle() }
            return upstream
        }
        var latency = upstream
        for slot in chains.chains[node] where slot.position == position {
            // A resumed worker must not replay the block it rendered before the pause.
            if slot.insert.fullyBypassed { slot.insert.markIdle(); continue }
            var source: UnsafeMutablePointer<Float>?
            var sourceLatency = 0
            var feedback = false
            if let bus = slot.sidechainBus {
                feedback = renderGraph.usesPreviousBlock(source: bus, target: target)
                // Current bus taps are post-inserts/fader/manual delay, before final output PDC.
                // Output PDC cannot be part of a graph dependency on a later output.
                source = feedback ? feedbackBusTaps[bus] : busMixBuffers[bus]
                if !feedback { sourceLatency = nodeLatencies[MixerTopology.node(bus)] }
            } else if let strip = slot.sidechain { source = stripTaps[strip] }
            let align = alignSidechains && source != nil && !feedback
            let mainDelay = align ? max(0, sourceLatency - latency) : 0
            let sideDelay = !feedback && source != nil ? max(0, latency - sourceLatency) : 0
            slot.insert.process(buffer, sidechain: source, upstreamLatency: 0, frames: frames, mainDelaySamples: mainDelay, sideDelaySamples: sideDelay)
            latency += mainDelay
            latency += slot.insert.latency
        }
        return latency
    }

    private func updateRenderGraph(_ chains: InsertChainSnapshot) {
        for i in 0..<MixerTopology.nodes { graphRouting[i] = 0; graphSidechains[i] = 0 }
        for strip in allStrips {
            for bus in allBuses where realtimeStripSettings[strip]?.routing[bus] == true {
                graphRouting[MixerTopology.node(strip)] |= 1 << MixerTopology.node(bus)
            }
        }
        for node in 0..<MixerTopology.nodes where cycleDisabledMask & (1 << UInt64(node)) == 0 {
            for slot in chains.chains[node] where !slot.insert.fullyBypassed {
                if let bus = slot.sidechainBus { graphSidechains[MixerTopology.node(bus)] |= 1 << node }
            }
        }
        if !renderGraph.matches(routing: graphRouting, sidechains: graphSidechains) {
            renderGraph.rebuild(routing: graphRouting, sidechains: graphSidechains)
        }
    }

    public func compensationSamples(target: InsertTarget) -> Int {
        os_unfair_lock_lock(stateLock); defer { os_unfair_lock_unlock(stateLock) }
        return publishedCompensation[SidechainRenderGraph.node(target)]
    }
    /// Plugin + IPC + alignment latency of a node at the end of its processing (last published cycle).
    public func nodeLatency(_ target: InsertTarget) -> Int {
        os_unfair_lock_lock(stateLock); defer { os_unfair_lock_unlock(stateLock) }
        return publishedNodeLatencies[SidechainRenderGraph.node(target)]
    }

    public func withStoppedAudio(_ work: () -> Void) {
        let resume = isRunning
        stop()
        work()
        if resume { start() }
    }

    public func configureClock(rate: Double?, frames: UInt32) throws {
        guard (32...4096).contains(frames), rate == nil || (rate!.isFinite && (8000...384000).contains(rate!)) else { throw AudioConfigurationError.message("Invalid clock settings.") }
        let resume = isRunning
        stop()
        defer { if resume { start() } }
        if let id = masterDeviceID {
            let oldRate = AudioDeviceManager.shared.getDeviceSampleRate(id: id)
            let oldFrames = AudioDeviceManager.shared.getDeviceBufferSize(id: id)
            defer {
                engineSampleRate = AudioDeviceManager.shared.getDeviceSampleRate(id: id)
                bufferSize = AudioDeviceManager.shared.getDeviceBufferSize(id: id)
                rebuildClockDependentIO()
                resetClockProcessing()
            }
            do {
                if let rate { try AudioDeviceManager.shared.setDeviceSampleRate(id: id, rate: rate) }
                try AudioDeviceManager.shared.setDeviceBufferSize(id: id, frames: frames)
            } catch {
                try? AudioDeviceManager.shared.setDeviceSampleRate(id: id, rate: oldRate)
                try? AudioDeviceManager.shared.setDeviceBufferSize(id: id, frames: oldFrames)
                throw error
            }
        } else {
            engineSampleRate = rate ?? engineSampleRate
            bufferSize = frames
            rebuildClockDependentIO()
            resetClockProcessing()
        }
    }

    private func resetClockProcessing() {
        for (_, dsp) in stripDSPs { dsp.reset() }
        for (_, dsp) in busDSPs { dsp.reset() }
        let slots = inserts.values.flatMap { $0 }
        // Relaunching a worker restores its last saved state; capture recent editor edits first.
        let relaunching = slots.filter { $0.needsRelaunch(rate: engineSampleRate, block: bufferSize) }
        for slot in relaunching { slot.requestSnapshot() }
        let deadline = Date().addingTimeInterval(0.5)
        while !relaunching.allSatisfy({ $0.snapshotReady }) && Date() < deadline { usleep(10_000) }
        for slot in slots { slot.prepare(rate: engineSampleRate, block: bufferSize) }
    }

    // Fallback timer when Master A1 is unassigned
    private var fallbackTimer: DispatchSourceTimer?
    private let fallbackQueue = DispatchQueue(label: "com.audiomeeter.fallbackTimer", qos: .userInteractive)

    // Mixing Scratch Memory
    private let maxFrameCapacity: Int = 4096
    private var stripMixBuffers: [StripID: UnsafeMutablePointer<Float>] = [:]
    private var busMixBuffers: [BusID: UnsafeMutablePointer<Float>] = [:]

    // Thread synchronization for configuration updates
    private let stateLock = os_unfair_lock_t.allocate(capacity: 1)

    // Current cached settings (protected by lock or atomic copy)
    private var stripSettings: [StripID: StripSettings] = [:]
    private var busSettings: [BusID: BusSettings] = [:]
    // Last complete settings snapshot used when the UI/configuration thread owns
    // stateLock. These dictionaries are only touched by the master callback.
    private var realtimeStripSettings: [StripID: StripSettings] = [:]
    private var realtimeBusSettings: [BusID: BusSettings] = [:]
    // The previous realtime snapshot is parked here and released by a non-realtime
    // thread under stateLock, so dictionary/String/EQ-array storage is never freed
    // on the render callback. The callback adopts a new snapshot only once drained.
    private var retiredStripSettings: [StripID: StripSettings]?
    private var retiredBusSettings: [BusID: BusSettings]?
    private func drainRetiredSettingsLocked() { retiredStripSettings = nil; retiredBusSettings = nil }

    public init() {
        stateLock.initialize(to: os_unfair_lock())
        mach_timebase_info(&timebase)
        vm_counter_store(optionFlags, Option.latencyCompensation.rawValue | Option.outputBusAlignment.rawValue | Option.sidechainAlignment.rawValue)
        vm_counter_store(packedBusOrder, BusProcessingStage.packed(BusProcessingStage.standard))
        vm_counter_store(chainPointer, UInt64(UInt(bitPattern: Unmanaged.passUnretained(currentChains).toOpaque())))

        for strip in allStrips {
            inputRingBuffers[strip] = StereoRingBuffer(capacityFrames: 16384)
            currentPans[strip] = 0
            stripDSPs[strip] = StripDSP()
            stripMeters[strip] = MeterLevel()
            stripSettings[strip] = StripSettings(
                routing: RoutingMatrix(a1: true, b1: strip.isHardware) // sensible defaults
            )
            realtimeStripMeters[strip] = MeterLevel()
            realtimeStripSettings[strip] = stripSettings[strip]

            let ptr = UnsafeMutablePointer<Float>.allocate(capacity: maxFrameCapacity * 2)
            ptr.initialize(repeating: 0.0, count: maxFrameCapacity * 2)
            stripMixBuffers[strip] = ptr
            let tap = UnsafeMutablePointer<Float>.allocate(capacity: maxFrameCapacity * 2)
            tap.initialize(repeating: 0, count: maxFrameCapacity * 2)
            stripTaps[strip] = tap; stripHistories[strip] = StereoSampleHistory()
        }

        for bus in allBuses {
            if bus != .A1 {
                outputRingBuffers[bus] = StereoRingBuffer(capacityFrames: 16384)
            }
            busDSPs[bus] = BusDSP()
            busMeters[bus] = MeterLevel()
            busSettings[bus] = BusSettings()
            realtimeBusMeters[bus] = MeterLevel()
            realtimeBusSettings[bus] = busSettings[bus]

            let ptr = UnsafeMutablePointer<Float>.allocate(capacity: maxFrameCapacity * 2)
            ptr.initialize(repeating: 0.0, count: maxFrameCapacity * 2)
            busMixBuffers[bus] = ptr
            let tap = UnsafeMutablePointer<Float>.allocate(capacity: maxFrameCapacity * 2)
            tap.initialize(repeating: 0, count: maxFrameCapacity * 2)
            busTaps[bus] = tap
            let feedbackTap = UnsafeMutablePointer<Float>.allocate(capacity: maxFrameCapacity * 2)
            feedbackTap.initialize(repeating: 0, count: maxFrameCapacity * 2)
            feedbackBusTaps[bus] = feedbackTap
            busDelays[bus] = StereoDelayLine()
            busOutputDelays[bus] = StereoDelayLine(); playbackDelays[bus] = StereoDelayLine()
        }
        routeScratch.initialize(repeating: 0, count: 8192)
    }

    deinit {
        stop()
        for (_, ptr) in stripMixBuffers { ptr.deallocate() }
        for (_, ptr) in busMixBuffers { ptr.deallocate() }
        for (_, ptr) in stripTaps { ptr.deallocate() }
        for ptr in busTaps.values { ptr.deallocate() }
        for ptr in feedbackBusTaps.values { ptr.deallocate() }
        routeScratch.deallocate()
        for counter in [heartbeat, disabledInsertMask, optionFlags, packedBusOrder, chainPointer, cycleNanos, cycleMaxNanos, cycleOverruns] { vm_counter_destroy(counter) }
        stateLock.deallocate()
    }

    #if VM_AUDIO_TESTS
    // Compile-time-only offline harness: exercises the actual mixer without device IO.
    func feedOffline(_ strip: StripID, _ samples: [Float]) {
        samples.withUnsafeBufferPointer { _ = inputRingBuffers[strip]?.write(from: $0.baseAddress!, frameCount: samples.count / 2) }
    }
    func renderOffline() -> [BusID: [Float]] {
        precondition(!isRunning)
        processMasterCycle(inputData: nil, outputData: nil)
        return Dictionary(uniqueKeysWithValues: allBuses.map { ($0, Array(UnsafeBufferPointer(start: busMixBuffers[$0]!, count: Int(bufferSize) * 2))) })
    }
    /// Offline render of the master device path, including same-device direct IO.
    func renderOfflineDevice(input: UnsafePointer<AudioBufferList>?, output: UnsafeMutablePointer<AudioBufferList>?) {
        precondition(!isRunning)
        processMasterCycle(inputData: input, outputData: output)
    }
    func setOfflineMaster(_ id: AudioObjectID?) { masterDeviceID = id }
    #endif

    // MARK: - Engine Lifecycle

    public func start() {
        guard !isRunning else { return }
        deviceErrors.removeAll(keepingCapacity: true)
        for (_, ring) in inputRingBuffers { ring.reset() }
        for (_, ring) in outputRingBuffers { ring.reset() }
        for tap in busTaps.values { tap.update(repeating: 0, count: maxFrameCapacity * 2) }; busTapFrames = 0
        for history in stripHistories.values { history.reset() }
        for tap in feedbackBusTaps.values { tap.update(repeating: 0, count: maxFrameCapacity * 2) }
        for delay in busDelays.values { delay.reset() }
        for delay in busOutputDelays.values { delay.reset() }
        for delay in playbackDelays.values { delay.reset() }
        for slots in inserts.values { for slot in slots { slot.reset() } }
        reclaimRetiredChains()
        isRunning = true

        // Start all input streams
        for (strip, input) in inputIOs {
            input.start()
            if let status = input.lastError { deviceErrors.append("\(strip.shortName): OSStatus \(status)") }
        }

        // Start all secondary output streams
        for (bus, output) in outputIOs {
            output.start()
            if let status = output.lastError { deviceErrors.append("\(bus.name): OSStatus \(status)") }
        }

        for (bus, output) in dawOutputs {
            dawRings[bus]?.reset(); output.start()
            if let status = output.lastError { deviceErrors.append("DAW \(bus.name): OSStatus \(status)") }
        }
        // Start master output or fallback timer
        if let masterID = masterDeviceID {
            startMasterIO(deviceID: masterID)
        } else {
            startFallbackTimer()
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        stopMasterIO()
        stopFallbackTimer()
        for output in dawOutputs.values { output.stop() }

        for (_, input) in inputIOs {
            input.stop()
        }
        for (_, output) in outputIOs {
            output.stop()
        }
        reclaimRetiredChains()
    }

    public func restartEngine() {
        stop()
        // Reset all ring buffers
        for (_, rb) in inputRingBuffers { rb.reset() }
        for (_, rb) in outputRingBuffers { rb.reset() }
        for (_, dsp) in stripDSPs { dsp.reset() }
        for (_, dsp) in busDSPs { dsp.reset() }
        start()
    }

    // MARK: - Device Configuration

    public func assignInputDevice(strip: StripID, device: AudioDeviceInfo?) {
        let resume = isRunning
        stop()
        defer { if resume { start() } }
        os_unfair_lock_lock(stateLock)
        stripSettings[strip]?.deviceUID = device?.uid
        drainRetiredSettingsLocked()
        os_unfair_lock_unlock(stateLock)
        stripDevices[strip] = device
        configureInputIO(strip)
    }

    /// Builds the IO for one strip from its stored device. Requires stopped IO.
    private func configureInputIO(_ strip: StripID) {
        let device = stripDevices[strip]
        inputIOs[strip]?.stop()
        inputIOs[strip] = nil
        inputRingBuffers[strip]?.reset()
        directInputs[strip.rawValue] = false

        if let bus = dawBus(for: strip) {
            dawOutputs[bus]?.stop(); dawOutputs[bus] = nil
            dawEndpoints[strip] = device.flatMap { DAWDuplexTransport.endpoint($0.id) }
            dawRings[bus]?.reset()
            if let endpoint = dawEndpoints[strip], let ring = dawRings[bus] {
                dawOutputs[bus] = AudioOutputIO(deviceID: endpoint, engineRate: engineSampleRate, ringBuffer: ring, channelOffset: 0, engineFrames: bufferSize)
            }
        }
        guard let dev = device, let ring = inputRingBuffers[strip] else { return }
        guard internalBus(dev.uid) == nil else { return }
        let actualID = dawEndpoints[strip] ?? dev.id
        if actualID == masterDeviceID { directInputs[strip.rawValue] = true; return }
        let io = AudioInputIO(deviceID: actualID, engineRate: engineSampleRate, ringBuffer: ring, channelOffset: stripSettings[strip]?.channelOffset ?? 0, leftChannel: stripSettings[strip]?.leftChannel, rightChannel: stripSettings[strip]?.rightChannel, engineFrames: bufferSize)
        inputIOs[strip] = io
    }

    public func assignOutputDevice(bus: BusID, device: AudioDeviceInfo?) {
        let resume = isRunning
        stop()
        defer { if resume { start() } }
        os_unfair_lock_lock(stateLock)
        busSettings[bus]?.deviceUID = device?.uid
        drainRetiredSettingsLocked()
        os_unfair_lock_unlock(stateLock)
        busDevices[bus] = device

        if bus == .A1 {
            // Bus A1 is Master Clock
            stopMasterIO()
            masterDeviceID = device?.id
            let oldRate = engineSampleRate
            let oldFrames = bufferSize
            if let dev = device {
                engineSampleRate = dev.sampleRate > 0 ? dev.sampleRate : 48000.0
                bufferSize = AudioDeviceManager.shared.getDeviceBufferSize(id: dev.id)
            }
            if abs(oldRate - engineSampleRate) >= 1.0 || oldFrames != bufferSize {
                rebuildClockDependentIO()
                resetClockProcessing()
            }
            // A different master changes which strips and buses are served directly.
            for strip in allStrips where stripDevices[strip] != nil { configureInputIO(strip) }
            for other in allBuses where other != .A1 && busDevices[other] != nil { configureOutputIO(other) }
        } else {
            configureOutputIO(bus)
        }
    }

    /// Builds the IO for one secondary bus from its stored device. Requires stopped IO.
    private func configureOutputIO(_ bus: BusID) {
        outputIOs[bus]?.stop()
        outputIOs[bus] = nil
        outputRingBuffers[bus]?.reset()
        directOutputs[bus.rawValue] = false
        guard let dev = busDevices[bus], let ring = outputRingBuffers[bus] else { return }
        if dev.id == masterDeviceID { directOutputs[bus.rawValue] = true; return }
        let io = AudioOutputIO(deviceID: dev.id, engineRate: engineSampleRate, ringBuffer: ring, channelOffset: busSettings[bus]?.channelOffset ?? 0, leftChannel: busSettings[bus]?.leftChannel, rightChannel: busSettings[bus]?.rightChannel, engineFrames: bufferSize)
        outputIOs[bus] = io
    }

    /// Input and secondary-output converters are constructed against the A1
    /// master clock. Recreate them whenever that clock rate changes. This also
    /// fixes startup, where virtual devices are commonly assigned before A1.
    private func rebuildClockDependentIO() {
        for (strip, endpoint) in dawEndpoints {
            guard let bus = dawBus(for: strip), let ring = dawRings[bus] else { continue }
            dawOutputs[bus]?.stop(); ring.reset()
            dawOutputs[bus] = AudioOutputIO(deviceID: endpoint, engineRate: engineSampleRate, ringBuffer: ring, channelOffset: 0, engineFrames: bufferSize)
        }
        let inputs = inputIOs.map { ($0.key, $0.value.deviceID, $0.value.channelOffset, $0.value.leftChannel, $0.value.rightChannel) }
        let outputs = outputIOs.map { ($0.key, $0.value.deviceID, $0.value.channelOffset, $0.value.leftChannel, $0.value.rightChannel) }

        for (_, io) in inputIOs { io.stop() }
        for (_, io) in outputIOs { io.stop() }
        inputIOs.removeAll(keepingCapacity: true)
        outputIOs.removeAll(keepingCapacity: true)

        for (strip, deviceID, channelOffset, leftChannel, rightChannel) in inputs {
            guard let ring = inputRingBuffers[strip] else { continue }
            ring.reset()
            let io = AudioInputIO(deviceID: deviceID, engineRate: engineSampleRate, ringBuffer: ring, channelOffset: channelOffset, leftChannel: leftChannel, rightChannel: rightChannel, engineFrames: bufferSize)
            inputIOs[strip] = io
        }
        for (bus, deviceID, channelOffset, leftChannel, rightChannel) in outputs {
            guard let ring = outputRingBuffers[bus] else { continue }
            ring.reset()
            let io = AudioOutputIO(deviceID: deviceID, engineRate: engineSampleRate, ringBuffer: ring, channelOffset: channelOffset, leftChannel: leftChannel, rightChannel: rightChannel, engineFrames: bufferSize)
            outputIOs[bus] = io
        }
    }

    public func reconcileDevices(_ devices: [AudioDeviceInfo]) {
        for strip in allStrips {
            let device = devices.first { $0.uid == stripSettings[strip]?.deviceUID }
            if internalBus(device?.uid) != nil && inputIOs[strip] == nil && !directInputs[strip.rawValue] { continue }
            let actualID = internalBus(device?.uid) != nil ? nil : dawBus(for: strip) != nil ? device.flatMap { DAWDuplexTransport.endpoint($0.id) } ?? device?.id : device?.id
            let wantsDirect = actualID != nil && actualID == masterDeviceID
            var changed: Bool
            if wantsDirect || directInputs[strip.rawValue] {
                changed = wantsDirect != directInputs[strip.rawValue] || stripDevices[strip]?.id != device?.id
            } else {
                changed = inputIOs[strip]?.deviceID != actualID || (device != nil && inputIOs[strip]?.deviceSampleRate != device?.sampleRate || (device != nil && inputIOs[strip]?.deviceBufferSize != AudioDeviceManager.shared.getDeviceBufferSize(id: device!.id)))
            }
            if changed {
                let saved = stripSettings[strip]?.deviceUID
                assignInputDevice(strip: strip, device: device)
                updateStripSettings(strip: strip) { $0.deviceUID = saved }
            }
        }
        for bus in allBuses {
            let device = devices.first { $0.uid == busSettings[bus]?.deviceUID }
            let direct = bus != .A1 && directOutputs[bus.rawValue]
            let currentID = bus == .A1 || direct ? (bus == .A1 ? masterDeviceID : busDevices[bus]?.id) : outputIOs[bus]?.deviceID
            let changedFrames = !direct && (device.map { AudioDeviceManager.shared.getDeviceBufferSize(id: $0.id) != (bus == .A1 ? bufferSize : outputIOs[bus]?.deviceBufferSize) } ?? false)
            let changedRate = device != nil && !direct && (bus == .A1 ? engineSampleRate : outputIOs[bus]?.deviceSampleRate) != device?.sampleRate
            let changedDirect = bus != .A1 && device != nil && (device?.id == masterDeviceID) != direct
            if changedFrames || currentID != device?.id || changedRate || changedDirect {
                let saved = busSettings[bus]?.deviceUID
                assignOutputDevice(bus: bus, device: device)
                updateBusSettings(bus: bus) { $0.deviceUID = saved }
            }
        }
    }

    // MARK: - Settings Updates

    public func updateStripSettings(strip: StripID, update: (inout StripSettings) -> Void) {
        os_unfair_lock_lock(stateLock)
        if var s = stripSettings[strip] {
            update(&s)
            stripSettings[strip] = s
        }
        drainRetiredSettingsLocked()
        os_unfair_lock_unlock(stateLock)
    }

    public func updateBusSettings(bus: BusID, update: (inout BusSettings) -> Void) {
        os_unfair_lock_lock(stateLock)
        if var b = busSettings[bus] {
            update(&b)
            busSettings[bus] = b
        }
        drainRetiredSettingsLocked()
        os_unfair_lock_unlock(stateLock)
    }

    public func getStripMeter(strip: StripID) -> MeterLevel {
        os_unfair_lock_lock(stateLock)
        defer { os_unfair_lock_unlock(stateLock) }
        drainRetiredSettingsLocked() // Meter polling also bounds how long a retired snapshot lives.
        return stripMeters[strip] ?? MeterLevel()
    }

    public func getBusMeter(bus: BusID) -> MeterLevel {
        os_unfair_lock_lock(stateLock)
        defer { os_unfair_lock_unlock(stateLock) }
        return busMeters[bus] ?? MeterLevel()
    }

    // MARK: - Master Audio Callback & Processing

    private func startMasterIO(deviceID: AudioObjectID) {
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, deviceID, nil) { [weak self] inNow, inInputData, inInputTime, outOutputData, outOutputTime in
            guard let self = self else { return }
            self.processMasterCycle(inputData: inInputData, outputData: outOutputData)
        }

        guard status == noErr, let validProc = proc else {
            deviceErrors.append("A1: IOProc creation failed (OSStatus \(status))")
            print("Failed to create master IOProc for device \(deviceID): status \(status)")
            startFallbackTimer()
            return
        }

        self.masterIOProcID = validProc
        let startStatus = AudioDeviceStart(deviceID, validProc)
        if startStatus != noErr {
            AudioDeviceDestroyIOProcID(deviceID, validProc)
            masterIOProcID = nil
            deviceErrors.append("A1: device start failed (OSStatus \(startStatus))")
            print("Failed to start master device \(deviceID): status \(startStatus)")
            startFallbackTimer()
        }
    }

    private func stopMasterIO() {
        if let masterID = masterDeviceID, let proc = masterIOProcID {
            AudioDeviceStop(masterID, proc)
            AudioDeviceDestroyIOProcID(masterID, proc)
            masterIOProcID = nil
        }
    }

    private func startFallbackTimer() {
        guard fallbackTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: fallbackQueue)
        let intervalNS = Int(Double(bufferSize) / engineSampleRate * 1_000_000_000.0)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(intervalNS), leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in
            self?.processMasterCycle(inputData: nil, outputData: nil)
        }
        timer.resume()
        self.fallbackTimer = timer
    }

    private func stopFallbackTimer() {
        fallbackTimer?.cancel()
        fallbackTimer = nil
        fallbackQueue.sync {}
    }

    @inline(__always) private func processStage(_ stage: BusProcessingStage, bus: BusID, buffer bBuf: UnsafeMutablePointer<Float>, dsp: BusDSP, setting: BusSettings, chains: InsertChainSnapshot, latency processedLatency: inout Int, frames clampedFrames: Int, alignSidechains: Bool) {
        switch stage {
        case .preInserts, .postInserts:
            processedLatency = processInserts(chains, target: .bus(bus), position: stage == .preInserts ? .pre : .post,
                                              buffer: bBuf, upstream: processedLatency, frames: clampedFrames, alignSidechains: alignSidechains)
        case .eq:
            if setting.isEQEnabled { dsp.processEQ(buffer: bBuf, frames: clampedFrames, sampleRate: Float(engineSampleRate), config: setting.eqConfig) }
            spectrumCapture.write(bus: bus, buffer: bBuf, frames: clampedFrames, sampleRate: Float(engineSampleRate))
        case .fader:
            dsp.process(buffer: bBuf, frames: clampedFrames, sampleRate: Float(engineSampleRate), gainDB: setting.gainDB,
                        isMuted: setting.isMuted, mode: setting.mode, limiterEnabled: false)
        case .limiter:
            dsp.processLimiter(buffer: bBuf, frames: clampedFrames, sampleRate: Float(engineSampleRate),
                               enabled: setting.isLimiterEnabled ?? true, thresholdDB: setting.limiterThresholdDB ?? -0.91515,
                               ceilingDB: setting.limiterCeilingDB ?? 0, lookaheadMS: setting.limiterLookaheadMS ?? 0)
            processedLatency += BusDSP.limiterLatency(sampleRate: Float(engineSampleRate), milliseconds: setting.limiterLookaheadMS ?? 0, enabled: setting.isLimiterEnabled ?? true)
        }
    }

    /// Core mixing and processing loop
    private func processMasterCycle(inputData: UnsafePointer<AudioBufferList>?, outputData: UnsafeMutablePointer<AudioBufferList>?) {
        let cycleStart = mach_absolute_time()
        var frameCount = Int(bufferSize)
        if let outData = outputData {
            frameCount = StereoAudioBufferIO.frameCount(outData)
        }
        let clampedFrames = min(frameCount, maxFrameCapacity)
        guard clampedFrames > 0 else {
            if let outputData { StereoAudioBufferIO.clear(outputData) }
            return
        }

        renderSequence &+= 1; vm_counter_store(heartbeat, renderSequence)
        // Load the chain snapshot after publishing the heartbeat (see reclaimRetiredChains).
        let chains = Unmanaged<InsertChainSnapshot>.fromOpaque(UnsafeRawPointer(bitPattern: UInt(vm_counter_load(chainPointer)))!).takeUnretainedValue()
        // Previous completed bus block is immutable during this render cycle.
        if clampedFrames > busTapFrames {
            for tap in busTaps.values { tap.advanced(by: busTapFrames * 2).update(repeating: 0, count: (clampedFrames - busTapFrames) * 2) }
            for tap in feedbackBusTaps.values { tap.advanced(by: busTapFrames * 2).update(repeating: 0, count: (clampedFrames - busTapFrames) * 2) }
        }
        // Never block the real-time callback behind UI work. If a control update
        // is in progress, use the previous complete snapshot for one cycle.
        if os_unfair_lock_trylock(stateLock) {
            if retiredStripSettings == nil && retiredBusSettings == nil {
                retiredStripSettings = realtimeStripSettings; realtimeStripSettings = stripSettings
                retiredBusSettings = realtimeBusSettings; realtimeBusSettings = busSettings
            }
            os_unfair_lock_unlock(stateLock)
        }
        cycleDisabledMask = vm_counter_load(disabledInsertMask)
        let flags = vm_counter_load(optionFlags)
        let latencyCompensation = flags & Option.latencyCompensation.rawValue != 0
        let outputAlignment = flags & Option.outputBusAlignment.rawValue != 0
        let sidechainAlignment = flags & Option.sidechainAlignment.rawValue != 0
        let busOrder = vm_counter_load(packedBusOrder)
        let localStripSettings = realtimeStripSettings
        let localBusSettings = realtimeBusSettings

        // Check if any strip is Solo
        let anySolo = localStripSettings.values.contains { $0.isSolo }

        updateRenderGraph(chains)
        for i in 0..<MixerTopology.nodes { nodeLatencies[i] = 0; realtimeCompensation[i] = 0 }
        // Snapshot every raw input before processing, so sidechains never depend on strip order.
        for strip in allStrips {
            if let buffer = stripMixBuffers[strip], let tap = stripTaps[strip] {
                if let bus = internalBus(localStripSettings[strip]?.deviceUID), let busTap = busTaps[bus] {
                    buffer.update(from: busTap, count: clampedFrames * 2)
                } else if directInputs[strip.rawValue] {
                    let setting = localStripSettings[strip]
                    let read = inputData.map { StereoAudioBufferIO.read($0, into: buffer, capacity: clampedFrames, channelOffset: setting?.channelOffset ?? 0, leftChannel: setting?.leftChannel, rightChannel: setting?.rightChannel) } ?? 0
                    if read < clampedFrames { buffer.advanced(by: read * 2).update(repeating: 0, count: (clampedFrames - read) * 2) }
                } else { inputRingBuffers[strip]?.readForPlayback(into: buffer, frameCount: clampedFrames) }
                tap.update(from: buffer, count: clampedFrames * 2)
            }
        }
        recorderPlayer?.renderPlayback(frames: clampedFrames, engineRate: engineSampleRate)
        // Render each dependency before its consumer. Only feedback edges read history.
        for node in renderGraph.order {
            if node < MixerTopology.strips {
                let strip = StripID(rawValue: node)!
                guard let mixBuf = stripMixBuffers[strip],
                      let dsp = stripDSPs[strip] else { continue }

                let setting = localStripSettings[strip] ?? StripSettings()
                let effectivelyMuted = setting.isMuted || (anySolo && !setting.isSolo)

                let preLatency = processInserts(chains, target: .strip(strip), position: .pre, buffer: mixBuf, upstream: 0, frames: clampedFrames, alignSidechains: sidechainAlignment)
                dsp.process(
                    buffer: mixBuf,
                    frames: clampedFrames,
                    sampleRate: Float(engineSampleRate),
                    gainDB: setting.gainDB,
                    isMuted: effectivelyMuted,
                    dynamicsConfig: setting.dynamics,
                    colorPad: setting.colorPad,
                    eq: setting.eq,
                    isVirtual: strip.isVirtual,
                    isKaraoke: setting.isKaraoke,
                    padMode: setting.padMode ?? .colorPan,
                    padState: setting.padMode == .pitch ? (setting.padPitch ?? PadState()) : setting.padMode == .formant ? (setting.padFormant ?? PadState()) : (setting.padModulation ?? PadState()),
                    pitchSmooth: setting.pitchSmooth ?? false
                )

                let pan = min(1, max(-1, (strip.isVirtual || setting.padMode == .pan) ? (setting.pan ?? 0) : 0))
                var smoothedPan = currentPans[strip] ?? 0
                let panStep = (pan - smoothedPan) / Float(clampedFrames)
                for frame in 0..<clampedFrames {
                    smoothedPan += panStep
                    mixBuf[frame * 2] *= smoothedPan > 0 ? 1 - smoothedPan : 1
                    mixBuf[frame * 2 + 1] *= smoothedPan < 0 ? 1 + smoothedPan : 1
                }
                currentPans[strip] = pan
                nodeLatencies[node] = processInserts(chains, target: .strip(strip), position: .post, buffer: mixBuf, upstream: preLatency + (strip.isVirtual ? 0 : InputPadDSP.latencyFrames(mode: setting.padMode ?? .colorPan, smooth: setting.pitchSmooth ?? false, rate: Float(engineSampleRate))), frames: clampedFrames, alignSidechains: sidechainAlignment)
                if effectivelyMuted { memset(mixBuf, 0, clampedFrames * 8) }
                // Unrouted (e.g. hidden) strips skip the history so its memory is never committed.
                let routed = allBuses.contains { setting.routing[$0] }
                if stripNeedsHistory[node] || (routed && (latencyCompensation || sidechainAlignment)) { stripHistories[strip]?.write(mixBuf, frames: clampedFrames) }
                else { stripHistories[strip]?.invalidate() }
                // Compute Strip Meter
                let prevMeter = realtimeStripMeters[strip] ?? MeterLevel()
                let newMeter = MeterCalculator.compute(
                    buffer: mixBuf,
                    frames: clampedFrames,
                    previousPeakL: prevMeter.leftPeakDB,
                    previousPeakR: prevMeter.rightPeakDB,
                    sampleRate: Float(engineSampleRate)
                )
                realtimeStripMeters[strip] = newMeter
            } else {
                let bus = BusID(rawValue: node - MixerTopology.strips)!
                guard let bBuf = busMixBuffers[bus], let dsp = busDSPs[bus] else { continue }
                let setting = localBusSettings[bus] ?? BusSettings()
                let alignRoutes = latencyCompensation || sidechainAlignment
                var incomingLatency = 0
                if alignRoutes {
                    for strip in allStrips where localStripSettings[strip]?.routing[bus] == true {
                        incomingLatency = max(incomingLatency, nodeLatencies[MixerTopology.node(strip)])
                    }
                }
                memset(bBuf, 0, clampedFrames * 8)
                for strip in allStrips where localStripSettings[strip]?.routing[bus] == true {
                    let delay = alignRoutes ? incomingLatency - nodeLatencies[MixerTopology.node(strip)] : 0
                    if delay == 0, let source = stripMixBuffers[strip] {
                        vDSP_vadd(bBuf, 1, source, 1, bBuf, 1, vDSP_Length(clampedFrames * 2))
                    } else {
                        stripHistories[strip]?.read(into: routeScratch, frames: clampedFrames, delay: delay)
                        vDSP_vadd(bBuf, 1, routeScratch, 1, bBuf, 1, vDSP_Length(clampedFrames * 2))
                    }
                    realtimeCompensation[strip.rawValue] = max(realtimeCompensation[strip.rawValue], delay)
                }
                // Tape playback is another zero-latency input to the bus summing point.
                routeScratch.update(repeating: 0, count: clampedFrames * 2)
                recorderPlayer?.mixRenderedPlayback(bus: bus, buffer: routeScratch, frames: clampedFrames)
                playbackDelays[bus]?.process(routeScratch, frames: clampedFrames, delay: incomingLatency)
                vDSP_vadd(bBuf, 1, routeScratch, 1, bBuf, 1, vDSP_Length(clampedFrames * 2))

                var processedLatency = incomingLatency
                for index in 0..<5 {
                    processStage(BusProcessingStage.unpacked(busOrder, at: index), bus: bus, buffer: bBuf, dsp: dsp, setting: setting, chains: chains,
                                 latency: &processedLatency, frames: clampedFrames, alignSidechains: sidechainAlignment)
                }
                let manualDelay = Int(min(500, max(0, setting.delayMilliseconds ?? 0)) * engineSampleRate / 1000)
                busManualLatencies[bus.rawValue] = manualDelay
                busDelays[bus]?.process(bBuf, frames: clampedFrames, delay: manualDelay)
                nodeLatencies[node] = processedLatency + manualDelay
                // Mute remains authoritative even when a post-fader plugin emits tails.
                if setting.isMuted { memset(bBuf, 0, clampedFrames * 8) }
            }
        }
        // Next cycle: keep delay history only for strips some route actually delays.
        for strip in allStrips { stripNeedsHistory[strip.rawValue] = realtimeCompensation[strip.rawValue] > 0 }

        // Freeze feedback sidechain taps before output-only PDC. Cyclic alignment is
        // deliberately excluded: L(a) >= L(b)+block and L(b) >= L(a)+block has no solution.
        for bus in allBuses {
            if let source = busMixBuffers[bus], let tap = feedbackBusTaps[bus] {
                tap.update(from: source, count: clampedFrames * 2)
            }
        }
        var maximumOutputLatency = 0
        for bus in allBuses { maximumOutputLatency = max(maximumOutputLatency, nodeLatencies[MixerTopology.node(bus)] - busManualLatencies[bus.rawValue]) }
        for bus in allBuses {
            guard let bBuf = busMixBuffers[bus] else { continue }
            let setting = localBusSettings[bus] ?? BusSettings()
            let delay = outputAlignment ? maximumOutputLatency - (nodeLatencies[MixerTopology.node(bus)] - busManualLatencies[bus.rawValue]) : 0
            realtimeCompensation[MixerTopology.node(bus)] = delay
            busOutputDelays[bus]?.process(bBuf, frames: clampedFrames, delay: delay)
            // Compute Bus Meter
            let prevMeter = realtimeBusMeters[bus] ?? MeterLevel()
            var newMeter = MeterCalculator.compute(
                buffer: bBuf,
                frames: clampedFrames,
                previousPeakL: prevMeter.leftPeakDB,
                previousPeakR: prevMeter.rightPeakDB,
                sampleRate: Float(engineSampleRate)
            )
            newMeter.limiterReductionDB = setting.isMuted ? 0 : (busDSPs[bus]?.limiterReductionDB ?? 0)
            realtimeBusMeters[bus] = newMeter

            if dawOutputs[bus] != nil { dawRings[bus]?.write(from: bBuf, frameCount: clampedFrames) }
            // Route Bus samples to destination
            if bus == .A1 {
                // Directly write to Master Hardware Output buffer if present
                if let outData = outputData {
                    StereoAudioBufferIO.write(bBuf, frames: clampedFrames, to: outData, channelOffset: setting.channelOffset ?? 0, leftChannel: setting.leftChannel, rightChannel: setting.rightChannel)
                }
            } else if directOutputs[bus.rawValue] {
                // Same device as A1: other channels of the master buffer. A1 (first in order) cleared it.
                if let outData = outputData {
                    StereoAudioBufferIO.write(bBuf, frames: clampedFrames, to: outData, channelOffset: setting.channelOffset ?? 0, leftChannel: setting.leftChannel, rightChannel: setting.rightChannel, clearFirst: false)
                }
            } else {
                // Secondary buses write to their ring buffers
                outputRingBuffers[bus]?.write(from: bBuf, frameCount: clampedFrames)
            }
        }

        // Tap Audio for Recorder
        for bus in allBuses {
            if let source = busMixBuffers[bus], let tap = busTaps[bus] { tap.update(from: source, count: clampedFrames * 2) }
        }
        busTapFrames = clampedFrames

        if let recorder = recorderPlayer, recorder.recordingActive {
            let recBuffer: UnsafePointer<Float>?
            switch recorder.realtimeRecordingSource.target {
            case .bus(let bus): recBuffer = busMixBuffers[bus].map { UnsafePointer($0) }
            case .strip(let strip): recBuffer = stripMixBuffers[strip].map { UnsafePointer($0) }
            }
            if let buf = recBuffer {
                recorder.pushRecordingFrames(buffer: buf, frames: clampedFrames)
            }
        }

        // Meter publication is best-effort; dropping one visual frame is always
        // preferable to missing an audio deadline.
        if os_unfair_lock_trylock(stateLock) {
            for i in 0..<MixerTopology.nodes { publishedCompensation[i] = realtimeCompensation[i]; publishedNodeLatencies[i] = nodeLatencies[i] }
            for strip in allStrips { stripMeters[strip] = realtimeStripMeters[strip] }
            for bus in allBuses { busMeters[bus] = realtimeBusMeters[bus] }
            os_unfair_lock_unlock(stateLock)
        }
        let elapsed = (mach_absolute_time() - cycleStart) * UInt64(timebase.numer) / UInt64(max(1, timebase.denom))
        vm_counter_store(cycleNanos, elapsed)
        if elapsed > vm_counter_load(cycleMaxNanos) { vm_counter_store(cycleMaxNanos, elapsed) }
        if Double(elapsed) > Double(clampedFrames) / engineSampleRate * 1e9 { vm_counter_store(cycleOverruns, vm_counter_load(cycleOverruns) + 1) }
    }

    // MARK: - Diagnostics (main thread)

    func diagnostics(resetPeak: Bool) -> EngineDiagnostics {
        var report = EngineDiagnostics()
        report.running = isRunning
        report.sampleRate = engineSampleRate
        report.bufferFrames = Int(bufferSize)
        report.cycles = vm_counter_load(heartbeat)
        report.cycleMicros = Double(vm_counter_load(cycleNanos)) / 1000
        report.cycleMaxMicros = Double(vm_counter_load(cycleMaxNanos)) / 1000
        report.cycleOverruns = vm_counter_load(cycleOverruns)
        if resetPeak { vm_counter_store(cycleMaxNanos, 0) }
        report.usingFallbackClock = isRunning && masterIOProcID == nil
        if let master = masterDeviceID { report.masterLatency = AudioDeviceManager.shared.deviceLatency(id: master) }
        for strip in allStrips {
            var item = EngineDiagnostics.Path(name: strip.shortName)
            if directInputs[strip.rawValue] { item.mode = .direct }
            else if internalBus(stripSettings[strip]?.deviceUID) != nil { item.mode = .internalReturn }
            else if let io = inputIOs[strip] {
                item.mode = .ring
                item.correctionPPM = io.correctionPPM
            }
            if let ring = inputRingBuffers[strip] {
                item.fill = ring.fillRatio(); item.underruns = ring.underruns; item.overflows = ring.overflows
            }
            item.latency = nodeLatency(.strip(strip))
            report.inputs.append(item)
        }
        for bus in allBuses {
            var item = EngineDiagnostics.Path(name: bus.name)
            if bus == .A1 { item.mode = masterDeviceID == nil ? .none : .master }
            else if directOutputs[bus.rawValue] { item.mode = .direct }
            else if let io = outputIOs[bus] {
                item.mode = .ring
                item.correctionPPM = io.correctionPPM
                if let ring = outputRingBuffers[bus] { item.fill = ring.fillRatio(); item.underruns = ring.underruns; item.overflows = ring.overflows }
            }
            item.latency = nodeLatency(.bus(bus)) + compensationSamples(target: .bus(bus))
            report.outputs.append(item)
        }
        return report
    }
}
