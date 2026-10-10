import Foundation
import CoreAudio
import AudioToolbox
import Accelerate
import VMNative

/// Audiomeeter Master Audio Engine coordinating the 5x5 routing matrix and DSP
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

    var inserts: [InsertTarget: [HostedInsert]] = [:] // Changed only with stopped IO.
    var disabledInsertTargets: Set<InsertTarget> = []
    var latencyCompensationEnabled = true
    var outputBusAlignmentEnabled = true
    var sidechainAlignmentEnabled = true
    private let heartbeat = vm_counter_create()!
    public var renderHeartbeat: UInt64 { vm_counter_load(heartbeat) }
    private var renderSequence: UInt64 = 0
    private var busTaps: [BusID: UnsafeMutablePointer<Float>] = [:]
    private var busTapFrames = 0
    private var feedbackBusTaps: [BusID: UnsafeMutablePointer<Float>] = [:]
    private var currentPans: [StripID: Float] = [:]
    private func internalBus(_ uid: String?) -> BusID? {
        switch uid { case "AudiomeeterB1_UID", "VoicemeeterB1_UID": return .B1; case "AudiomeeterB2_UID", "VoicemeeterB2_UID": return .B2; default: return nil }
    }
    private var stripTaps: [StripID: UnsafeMutablePointer<Float>] = [:]
    private var stripHistories: [StripID: StereoSampleHistory] = [:]
    private var busDelays: [BusID: StereoDelayLine] = [:]
    private var busOutputDelays: [BusID: StereoDelayLine] = [:]
    private var playbackDelays: [BusID: StereoDelayLine] = [:]
    private let routeScratch = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
    private var graphRouting = [UInt16](repeating: 0, count: 10)
    private var graphSidechains = [UInt16](repeating: 0, count: 10)
    private var renderGraph = SidechainRenderGraph(routingEdges: [UInt16](repeating: 0, count: 10), sidechainEdges: [UInt16](repeating: 0, count: 10))
    private var nodeLatencies = [Int](repeating: 0, count: 10)
    private var busManualLatencies = [Int](repeating: 0, count: 5)
    private var realtimeCompensation: [InsertTarget: Int] = [:]
    private var publishedCompensation: [InsertTarget: Int] = [:]
    func insertLatency(_ target: InsertTarget) -> Int {
        disabledInsertTargets.contains(target) ? 0 : (inserts[target] ?? []).reduce(0) { $0 + ($1.bypassed ? 0 : $1.latency) }
    }
    private func processInserts(target: InsertTarget, position: InsertPosition, buffer: UnsafeMutablePointer<Float>, upstream: Int, frames: Int) -> Int {
        guard !disabledInsertTargets.contains(target) else { return upstream }
        var latency = upstream
        for slot in inserts[target] ?? [] where slot.position == position && !slot.bypassed {
            var source: UnsafeMutablePointer<Float>?
            var sourceLatency = 0
            var feedback = false
            if let bus = slot.sidechainBus {
                feedback = renderGraph.usesPreviousBlock(source: bus, target: target)
                // Current bus taps are post-inserts/fader/manual delay, before final output PDC.
                // Output PDC cannot be part of a graph dependency on a later output.
                source = feedback ? feedbackBusTaps[bus] : busMixBuffers[bus]
                if !feedback { sourceLatency = nodeLatencies[5 + bus.rawValue] }
            } else if let strip = slot.sidechain { source = stripTaps[strip] }
            let align = sidechainAlignmentEnabled && source != nil && !feedback
            let mainDelay = align ? max(0, sourceLatency - latency) : 0
            let sideDelay = !feedback && source != nil ? max(0, latency - sourceLatency) : 0
            slot.process(buffer, sidechain: source, upstreamLatency: 0, frames: frames, mainDelaySamples: mainDelay, sideDelaySamples: sideDelay)
            latency += mainDelay
            latency += slot.latency
        }
        return latency
    }

    private func updateRenderGraph() {
        for i in 0..<10 { graphRouting[i] = 0; graphSidechains[i] = 0 }
        for strip in allStrips {
            for bus in allBuses where realtimeStripSettings[strip]?.routing[bus] == true {
                graphRouting[strip.rawValue] |= 1 << (5 + bus.rawValue)
            }
        }
        for (target, slots) in inserts where !disabledInsertTargets.contains(target) {
            for slot in slots where !slot.bypassed {
                if let bus = slot.sidechainBus { graphSidechains[5 + bus.rawValue] |= 1 << SidechainRenderGraph.node(target) }
            }
        }
        if graphRouting != renderGraph.routingEdges || graphSidechains != renderGraph.sidechainEdges {
            renderGraph = SidechainRenderGraph(routingEdges: graphRouting, sidechainEdges: graphSidechains)
        }
    }

    public func compensationSamples(target: InsertTarget) -> Int {
        os_unfair_lock_lock(stateLock); defer { os_unfair_lock_unlock(stateLock) }
        return publishedCompensation[target] ?? 0
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
        for (_, slots) in inserts { for slot in slots { slot.prepare(rate: engineSampleRate, block: bufferSize) } }
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

    public init() {
        stateLock.initialize(to: os_unfair_lock())

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
            realtimeCompensation[.strip(strip)] = 0
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
            realtimeCompensation[.bus(bus)] = 0
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
        vm_counter_destroy(heartbeat)
        stateLock.deallocate()
    }

    #if VM_AUDIO_TESTS
    // Compile-time-only offline harness: exercises the actual mixer without device IO.
    func feedOffline(_ strip: StripID, _ samples: [Float]) {
        samples.withUnsafeBufferPointer { _ = inputRingBuffers[strip]?.write(from: $0.baseAddress!, frameCount: samples.count / 2) }
    }
    func renderOffline() -> [BusID: [Float]] {
        precondition(!isRunning)
        processMasterCycle(outputData: nil)
        return Dictionary(uniqueKeysWithValues: allBuses.map { ($0, Array(UnsafeBufferPointer(start: busMixBuffers[$0]!, count: Int(bufferSize) * 2))) })
    }
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
        os_unfair_lock_unlock(stateLock)

        // Stop existing worker
        inputIOs[strip]?.stop()
        inputIOs[strip] = nil
        inputRingBuffers[strip]?.reset()

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
        let io = AudioInputIO(deviceID: actualID, engineRate: engineSampleRate, ringBuffer: ring, channelOffset: stripSettings[strip]?.channelOffset ?? 0, leftChannel: stripSettings[strip]?.leftChannel, rightChannel: stripSettings[strip]?.rightChannel, engineFrames: bufferSize)
        inputIOs[strip] = io
    }

    public func assignOutputDevice(bus: BusID, device: AudioDeviceInfo?) {
        let resume = isRunning
        stop()
        defer { if resume { start() } }
        os_unfair_lock_lock(stateLock)
        busSettings[bus]?.deviceUID = device?.uid
        os_unfair_lock_unlock(stateLock)

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
        } else {
            outputIOs[bus]?.stop()
            outputIOs[bus] = nil
            outputRingBuffers[bus]?.reset()

            guard let dev = device, let ring = outputRingBuffers[bus] else { return }

            let io = AudioOutputIO(deviceID: dev.id, engineRate: engineSampleRate, ringBuffer: ring, channelOffset: busSettings[bus]?.channelOffset ?? 0, leftChannel: busSettings[bus]?.leftChannel, rightChannel: busSettings[bus]?.rightChannel, engineFrames: bufferSize)
            outputIOs[bus] = io
        }
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
            if internalBus(device?.uid) != nil && inputIOs[strip] == nil { continue }
            let actualID = internalBus(device?.uid) != nil ? nil : dawBus(for: strip) != nil ? device.flatMap { DAWDuplexTransport.endpoint($0.id) } ?? device?.id : device?.id
            if inputIOs[strip]?.deviceID != actualID || (device != nil && inputIOs[strip]?.deviceSampleRate != device?.sampleRate || (device != nil && inputIOs[strip]?.deviceBufferSize != AudioDeviceManager.shared.getDeviceBufferSize(id: device!.id))) {
                let saved = stripSettings[strip]?.deviceUID
                assignInputDevice(strip: strip, device: device)
                updateStripSettings(strip: strip) { $0.deviceUID = saved }
            }
        }
        for bus in allBuses {
            let device = devices.first { $0.uid == busSettings[bus]?.deviceUID }
            let currentID = bus == .A1 ? masterDeviceID : outputIOs[bus]?.deviceID
            let changedFrames = device.map { AudioDeviceManager.shared.getDeviceBufferSize(id: $0.id) != (bus == .A1 ? bufferSize : outputIOs[bus]?.deviceBufferSize) } ?? false
            if changedFrames || currentID != device?.id || (device != nil && (bus == .A1 ? engineSampleRate : outputIOs[bus]?.deviceSampleRate) != device?.sampleRate) {
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
        os_unfair_lock_unlock(stateLock)
    }

    public func updateBusSettings(bus: BusID, update: (inout BusSettings) -> Void) {
        os_unfair_lock_lock(stateLock)
        if var b = busSettings[bus] {
            update(&b)
            busSettings[bus] = b
        }
        os_unfair_lock_unlock(stateLock)
    }

    public func getStripMeter(strip: StripID) -> MeterLevel {
        os_unfair_lock_lock(stateLock)
        defer { os_unfair_lock_unlock(stateLock) }
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
            self.processMasterCycle(outputData: outOutputData)
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
            self?.processMasterCycle(outputData: nil)
        }
        timer.resume()
        self.fallbackTimer = timer
    }

    private func stopFallbackTimer() {
        fallbackTimer?.cancel()
        fallbackTimer = nil
        fallbackQueue.sync {}
    }

    /// Core 5x5 Matrix Mixing and Processing loop
    private func processMasterCycle(outputData: UnsafeMutablePointer<AudioBufferList>?) {
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
        // Previous completed bus block is immutable during this render cycle.
        if clampedFrames > busTapFrames {
            for taps in [busTaps, feedbackBusTaps] {
                for tap in taps.values { tap.advanced(by: busTapFrames * 2).update(repeating: 0, count: (clampedFrames - busTapFrames) * 2) }
            }
        }
        // Never block the real-time callback behind UI work. If a control update
        // is in progress, use the previous complete snapshot for one cycle.
        if os_unfair_lock_trylock(stateLock) {
            realtimeStripSettings = stripSettings
            realtimeBusSettings = busSettings
            os_unfair_lock_unlock(stateLock)
        }
        let localStripSettings = realtimeStripSettings
        let localBusSettings = realtimeBusSettings

        // Check if any strip is Solo
        let anySolo = localStripSettings.values.contains { $0.isSolo }

        updateRenderGraph()
        for i in 0..<10 { nodeLatencies[i] = 0 }
        for target in allInsertTargets { realtimeCompensation[target] = 0 }
        // Snapshot every raw input before processing, so sidechains never depend on strip order.
        for strip in allStrips {
            if let buffer = stripMixBuffers[strip], let tap = stripTaps[strip] {
                if let bus = internalBus(localStripSettings[strip]?.deviceUID), let busTap = busTaps[bus] {
                    buffer.update(from: busTap, count: clampedFrames * 2)
                } else { inputRingBuffers[strip]?.readForPlayback(into: buffer, frameCount: clampedFrames) }
                tap.update(from: buffer, count: clampedFrames * 2)
            }
        }
        recorderPlayer?.renderPlayback(frames: clampedFrames, engineRate: engineSampleRate)
        // Render each dependency before its consumer. Only feedback edges read history.
        for node in renderGraph.order {
            if node < 5 {
                let strip = StripID(rawValue: node)!
                guard let mixBuf = stripMixBuffers[strip],
                      let dsp = stripDSPs[strip] else { continue }

                let setting = localStripSettings[strip] ?? StripSettings()
                let effectivelyMuted = setting.isMuted || (anySolo && !setting.isSolo)

                let preLatency = processInserts(target: .strip(strip), position: .pre, buffer: mixBuf, upstream: 0, frames: clampedFrames)
                dsp.process(
                    buffer: mixBuf,
                    frames: clampedFrames,
                    sampleRate: Float(engineSampleRate),
                    gainDB: setting.gainDB,
                    isMuted: effectivelyMuted,
                    dynamicsConfig: setting.dynamics,
                    intellipan: setting.intellipan,
                    eq: setting.eq,
                    isVirtual: strip.isVirtual,
                    isKaraoke: setting.isKaraoke
                )

                let pan = min(1, max(-1, setting.pan ?? 0))
                var smoothedPan = currentPans[strip] ?? 0
                let panStep = (pan - smoothedPan) / Float(clampedFrames)
                for frame in 0..<clampedFrames {
                    smoothedPan += panStep
                    mixBuf[frame * 2] *= smoothedPan > 0 ? 1 - smoothedPan : 1
                    mixBuf[frame * 2 + 1] *= smoothedPan < 0 ? 1 + smoothedPan : 1
                }
                currentPans[strip] = pan
                nodeLatencies[node] = processInserts(target: .strip(strip), position: .post, buffer: mixBuf, upstream: preLatency, frames: clampedFrames)
                if effectivelyMuted { memset(mixBuf, 0, clampedFrames * 8) }
                stripHistories[strip]?.write(mixBuf, frames: clampedFrames)
                // Compute Strip Meter
                let prevMeter = realtimeStripMeters[strip] ?? MeterLevel()
                let newMeter = MeterCalculator.compute(
                    buffer: mixBuf,
                    frames: clampedFrames,
                    previousPeakL: prevMeter.leftPeakDB,
                    previousPeakR: prevMeter.rightPeakDB
                )
                realtimeStripMeters[strip] = newMeter
            } else {
                let bus = BusID(rawValue: node - 5)!
                guard let bBuf = busMixBuffers[bus], let dsp = busDSPs[bus] else { continue }
                let setting = localBusSettings[bus] ?? BusSettings()
                let alignRoutes = latencyCompensationEnabled || sidechainAlignmentEnabled
                var incomingLatency = 0
                if alignRoutes {
                    for strip in allStrips where localStripSettings[strip]?.routing[bus] == true {
                        incomingLatency = max(incomingLatency, nodeLatencies[strip.rawValue])
                    }
                }
                memset(bBuf, 0, clampedFrames * 8)
                for strip in allStrips where localStripSettings[strip]?.routing[bus] == true {
                    let delay = alignRoutes ? incomingLatency - nodeLatencies[strip.rawValue] : 0
                    stripHistories[strip]?.read(into: routeScratch, frames: clampedFrames, delay: delay)
                    realtimeCompensation[.strip(strip)] = max(realtimeCompensation[.strip(strip)] ?? 0, delay)
                    vDSP_vadd(bBuf, 1, routeScratch, 1, bBuf, 1, vDSP_Length(clampedFrames * 2))
                }
                // Tape playback is another zero-latency input to the bus summing point.
                routeScratch.update(repeating: 0, count: clampedFrames * 2)
                recorderPlayer?.mixRenderedPlayback(bus: bus, buffer: routeScratch, frames: clampedFrames)
                playbackDelays[bus]?.process(routeScratch, frames: clampedFrames, delay: incomingLatency)
                vDSP_vadd(bBuf, 1, routeScratch, 1, bBuf, 1, vDSP_Length(clampedFrames * 2))

                let preLatency = processInserts(target: .bus(bus), position: .pre, buffer: bBuf, upstream: incomingLatency, frames: clampedFrames)
                dsp.process(
                    buffer: bBuf,
                    frames: clampedFrames,
                    sampleRate: Float(engineSampleRate),
                    gainDB: setting.gainDB,
                    isMuted: setting.isMuted,
                    mode: setting.mode,
                    isEQEnabled: setting.isEQEnabled,
                    eqConfig: setting.eqConfig,
                    limiterEnabled: setting.isLimiterEnabled ?? true
                )

                let processedLatency = processInserts(target: .bus(bus), position: .post, buffer: bBuf, upstream: preLatency, frames: clampedFrames)
                let manualDelay = Int(min(500, max(0, setting.delayMilliseconds ?? 0)) * engineSampleRate / 1000)
                busManualLatencies[bus.rawValue] = manualDelay
                busDelays[bus]?.process(bBuf, frames: clampedFrames, delay: manualDelay)
                nodeLatencies[node] = processedLatency + manualDelay
                // Mute remains authoritative even when a post-fader plugin emits tails.
                if setting.isMuted { memset(bBuf, 0, clampedFrames * 8) }
            }
        }

        // Freeze feedback sidechain taps before output-only PDC. Cyclic alignment is
        // deliberately excluded: L(a) >= L(b)+block and L(b) >= L(a)+block has no solution.
        for bus in allBuses {
            if let source = busMixBuffers[bus], let tap = feedbackBusTaps[bus] {
                tap.update(from: source, count: clampedFrames * 2)
            }
        }
        var maximumOutputLatency = 0
        for bus in allBuses { maximumOutputLatency = max(maximumOutputLatency, nodeLatencies[5 + bus.rawValue] - busManualLatencies[bus.rawValue]) }
        for bus in allBuses {
            guard let bBuf = busMixBuffers[bus] else { continue }
            let setting = localBusSettings[bus] ?? BusSettings()
            let delay = outputBusAlignmentEnabled ? maximumOutputLatency - (nodeLatencies[5 + bus.rawValue] - busManualLatencies[bus.rawValue]) : 0
            realtimeCompensation[.bus(bus)] = delay
            busOutputDelays[bus]?.process(bBuf, frames: clampedFrames, delay: delay)
            // Compute Bus Meter
            let prevMeter = realtimeBusMeters[bus] ?? MeterLevel()
            let newMeter = MeterCalculator.compute(
                buffer: bBuf,
                frames: clampedFrames,
                previousPeakL: prevMeter.leftPeakDB,
                previousPeakR: prevMeter.rightPeakDB
            )
            realtimeBusMeters[bus] = newMeter

            if dawOutputs[bus] != nil { dawRings[bus]?.write(from: bBuf, frameCount: clampedFrames) }
            // Route Bus samples to destination
            if bus == .A1 {
                // Directly write to Master Hardware Output buffer if present
                if let outData = outputData {
                    StereoAudioBufferIO.write(bBuf, frames: clampedFrames, to: outData, channelOffset: setting.channelOffset ?? 0, leftChannel: setting.leftChannel, rightChannel: setting.rightChannel)
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
            var recBuffer: UnsafePointer<Float>?
            switch recorder.realtimeRecordingSource {
            case .busA1: recBuffer = UnsafePointer(busMixBuffers[.A1])
            case .busA2: recBuffer = UnsafePointer(busMixBuffers[.A2])
            case .busA3: recBuffer = UnsafePointer(busMixBuffers[.A3])
            case .busB1: recBuffer = UnsafePointer(busMixBuffers[.B1])
            case .busB2: recBuffer = UnsafePointer(busMixBuffers[.B2])
            case .strip1: recBuffer = UnsafePointer(stripMixBuffers[.hardware1])
            case .strip2: recBuffer = UnsafePointer(stripMixBuffers[.hardware2])
            case .strip3: recBuffer = UnsafePointer(stripMixBuffers[.hardware3])
            case .stripVAIO: recBuffer = UnsafePointer(stripMixBuffers[.virtualVAIO])
            case .stripAUX: recBuffer = UnsafePointer(stripMixBuffers[.virtualAUX])
            }
            if let buf = recBuffer {
                recorder.pushRecordingFrames(buffer: buf, frames: clampedFrames)
            }
        }

        // Meter publication is best-effort; dropping one visual frame is always
        // preferable to missing an audio deadline.
        if os_unfair_lock_trylock(stateLock) {
            publishedCompensation = realtimeCompensation
            for strip in allStrips { stripMeters[strip] = realtimeStripMeters[strip] }
            for bus in allBuses { busMeters[bus] = realtimeBusMeters[bus] }
            os_unfair_lock_unlock(stateLock)
        }
    }
}
