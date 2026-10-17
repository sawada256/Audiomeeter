import Foundation
import Darwin
import VMNative

public struct InsertConfig: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var path: String
    public var name: String
    public var position: InsertPosition
    public var bypassed = false
    public var state = ""
    public var identifier: String? = nil
    public var sidechain: StripID? = nil
    public var sidechainBus: BusID? = nil
    public var savedLatency: Int? = nil
    /// nil on legacy settings, where a bypass was always a full bypass.
    public var bypassMode: InsertBypassMode? = nil
    /// MIDI input to the plugin: nil = off, 0 = all channels, 1...16 = one channel.
    public var midiInput: Int? = nil
    var effectiveBypass: InsertBypassMode? { bypassed ? (bypassMode ?? .full) : nil }
    var isFullyBypassed: Bool { effectiveBypass == .full }
    var isSoftBypassed: Bool { effectiveBypass == .latency }
}

struct PluginParameterInfo: Codable, Identifiable, Equatable {
    var index: Int
    var name: String
    var value: Float
    var automatable: Bool?
    var id: Int { index }
}

/// Forwards controller MIDI from the CoreMIDI thread straight into worker rings.
/// Registration is locked; this is not the audio thread, and workers drain lock-free.
final class MIDIPluginRouter: @unchecked Sendable {
    static let shared = MIDIPluginRouter()
    private var lock = os_unfair_lock()
    private var routes: [ObjectIdentifier: (handle: UnsafeMutableRawPointer, channel: Int)] = [:]
    func register(_ owner: AnyObject, handle: UnsafeMutableRawPointer, channel: Int) {
        os_unfair_lock_lock(&lock); routes[ObjectIdentifier(owner)] = (handle, channel); os_unfair_lock_unlock(&lock)
    }
    func unregister(_ owner: AnyObject) {
        os_unfair_lock_lock(&lock); routes[ObjectIdentifier(owner)] = nil; os_unfair_lock_unlock(&lock)
    }
    /// One MIDI 1.0 channel-voice message (status, data1, data2).
    func forward(status: UInt8, data1: UInt8, data2: UInt8) {
        guard status >= 0x80, status < 0xF0 else { return }
        let message = UInt32(status) | UInt32(data1) << 8 | UInt32(data2) << 16
        let channel = Int(status & 0x0F) + 1
        os_unfair_lock_lock(&lock)
        for route in routes.values where route.channel == 0 || route.channel == channel { _ = vmw_midi_push(route.handle, message) }
        os_unfair_lock_unlock(&lock)
    }
    var isEmpty: Bool { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return routes.isEmpty }
}

/// Each instance owns a disposable worker process. The mixer never calls plugin code.
/// Routing fields (position, sidechain) are captured by InsertChainSnapshot; changing
/// them publishes a new snapshot instead of mutating a slot the callback is using.
final class HostedInsert {
    var config: InsertConfig
    // 0 active, 1 soft (latency-preserving) bypass, 2 full bypass. Atomic: changes while audio runs.
    private let bypassCounter = vm_counter_create()!
    var fullyBypassed: Bool { vm_counter_load(bypassCounter) == 2 }
    /// Legacy name used by tests and latency accounting: true only for a full bypass.
    var bypassed: Bool { fullyBypassed }
    func setBypass(_ mode: InsertBypassMode?) {
        config.bypassed = mode != nil; config.bypassMode = mode
        applyBypass()
    }
    func setBypassed(_ value: Bool) { setBypass(value ? (config.bypassMode ?? .full) : nil) }
    private func applyBypass() {
        let state: UInt64 = config.effectiveBypass == .full ? 2 : config.effectiveBypass == .latency ? 1 : 0
        vm_counter_store(bypassCounter, state)
        if let handle { vmw_set_soft_bypass(handle, state == 1 ? 1 : 0) }
    }
    func updateControls() { applyBypass(); applyMIDIRoute() }
    func setMIDIInput(_ channel: Int?) { config.midiInput = channel.map { min(16, max(0, $0)) }; applyMIDIRoute() }
    private func applyMIDIRoute() {
        if let handle, let channel = config.midiInput { MIDIPluginRouter.shared.register(self, handle: handle, channel: channel) }
        else { MIDIPluginRouter.shared.unregister(self) }
    }
    // Render-callback only: set while the slot is skipped, consumed by the next process call.
    private var idle = false
    func markIdle() { idle = true }
    private var handle: UnsafeMutableRawPointer!
    private var worker: Process?
    private var directory: URL!
    private var semaphore = ""
    private var started = Date()
    private let sideDelay = StereoDelayLine()
    private let mainDelay = StereoDelayLine()
    private let alignmentCounter = vm_counter_create()!
    var alignmentDelaySamples: Int { Int(vm_counter_load(alignmentCounter)) }
    private let sideBuffer = UnsafeMutablePointer<Float>.allocate(capacity: 8192)
    private var faultMessage: String?
    private var rate: Double = 48000
    private var block: UInt32 = 256
    private var snapshotToken: UInt64 = 0
    private var editorToken: UInt64 = 0
    private var editorRequested: Date?
    private var editorRecoveries = 0
    private(set) var parameters: [PluginParameterInfo] = []
    private var parametersLoaded = false
    var needsEditorRecovery: Bool {
        guard let handle, vmw_ready(handle) == 1, let editorRequested else { return false }
        return editorRecoveries < 1 && vmw_editor_ack(handle) < editorToken && Date().timeIntervalSince(editorRequested) > 5
    }
    func recoverEditor() { editorRecoveries += 1; retry(); requestEditor() }
    private func requestEditor() {
        if let handle { editorToken = vmw_editor(handle); editorRequested = Date() }
    }

    init(config: InsertConfig, rate: Double, block: UInt32) throws {
        self.config = config
        sideBuffer.initialize(repeating: 0, count: 8192)
        do { try launch(rate: rate, block: block) } catch { dispose(); sideBuffer.deallocate(); vm_counter_destroy(alignmentCounter); vm_counter_destroy(bypassCounter); throw error }
        updateControls()
    }
    deinit { dispose(); sideBuffer.deallocate(); vm_counter_destroy(alignmentCounter); vm_counter_destroy(bypassCounter) }
    private func launch(rate: Double, block: UInt32) throws {
        self.rate = rate; self.block = block; faultMessage = nil; started = Date(); parametersLoaded = false
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("audiomeeter-worker-\(token)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        semaphore = "/vmw-" + token.prefix(20)
        handle = vmw_open(directory.appendingPathComponent("audio").path, semaphore, Int32(block), rate)
        guard handle != nil else { throw AudioConfigurationError.message(L10n.text("プラグインIPCを作成できませんでした。")) }
        vmw_seed_latency(handle, Int32(config.savedLatency ?? 0))
        let settings: [String: Any] = ["path": config.path, "identifier": config.identifier ?? "", "state": config.state,
            "rate": rate, "shared": directory.appendingPathComponent("audio").path, "semaphore": semaphore,
            "metadata": directory.appendingPathComponent("metadata.json").path, "parentPID": ProcessInfo.processInfo.processIdentifier]
        let file = directory.appendingPathComponent("config.json")
        try JSONSerialization.data(withJSONObject: settings).write(to: file, options: .atomic)
        let process = Process(); process.executableURL = PluginRuntime.workerURL
        var environment = ProcessInfo.processInfo.environment
        environment["AUDIOMEETER_LANGUAGE"] = LocalizationStore.shared.language
        process.environment = environment
        process.arguments = [file.path]; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); worker = process }
        catch { dispose(); throw error }
        applyBypass(); applyMIDIRoute()
    }
    private func dispose() {
        editorRequested = nil; editorToken = 0
        MIDIPluginRouter.shared.unregister(self) // Before the shared memory goes away.
        if let process = worker, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now()+0.2) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        }
        worker = nil
        if let handle { vmw_close(handle); self.handle = nil }
        if !semaphore.isEmpty { sem_unlink(semaphore); semaphore = "" }
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
    var workerProcessID: Int32? { worker?.processIdentifier }
    var latency: Int { handle == nil ? Int(block) : max(Int(block), Int(vmw_latency(handle))) }
    var sidechainChannels: Int { handle == nil ? 0 : Int(vmw_side_channels(handle)) }
    var lateBlocks: UInt64 { handle == nil ? 0 : vmw_late(handle) }
    var renderMicros: Double { handle == nil ? 0 : Double(vmw_render_micros(handle)) }
    var hasBypassParameter: Bool { handle != nil && vmw_has_bypass_parameter(handle) != 0 }
    /// Fault reason from the transport: 0 none, 1 load failure, 2 crash, 3 late/timeout, 4 bad latency.
    var faultCode: Int { handle == nil ? 1 : Int(vmw_fault(handle)) }
    var isLoaded: Bool { handle != nil && vmw_ready(handle) == 1 }
    var status: String {
        if let faultMessage { return faultMessage }
        guard handle != nil else { return L10n.text("ワーカーを起動できませんでした") }
        if vmw_fault(handle) != 0 { return L10n.text("処理が間に合いません。遅延を保ってバイパス中") }
        return vmw_ready(handle) == 0 ? L10n.text("読込中…") : ""
    }
    func refresh() {
        guard let handle else { return }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("metadata.json")),
           let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let name = metadata["name"] as? String { config.name = name }
            if let state = metadata["state"] as? String { config.state = state }
            if let error = metadata["error"] as? String { faultMessage = error }
        }
        if !parametersLoaded, vmw_ready(handle) == 1,
           let data = try? Data(contentsOf: directory.appendingPathComponent("parameters.json")),
           let list = try? JSONDecoder().decode([PluginParameterInfo].self, from: data) {
            parameters = list; parametersLoaded = true
        }
        if vmw_ready(handle) == 2 { faultMessage = faultMessage ?? L10n.text("プラグインを読み込めませんでした"); vmw_set_fault(handle, 1) }
        if let worker, !worker.isRunning { faultMessage = faultMessage ?? L10n.text("プラグインが終了しました（遅延を保ってバイパス中）"); vmw_set_fault(handle, 2) }
        if vmw_ready(handle) == 0 && Date().timeIntervalSince(started) > 15 { faultMessage = L10n.text("プラグインの読込がタイムアウトしました"); vmw_set_fault(handle, 3) }
        if vmw_fault(handle) != 0, let worker, worker.isRunning { kill(worker.processIdentifier, SIGKILL) }
        config.savedLatency = max(0, latency - Int(block))
    }
    /// Sends a normalized (0...1) parameter value to the plugin (main thread).
    func setParameter(_ index: Int, _ value: Float) {
        guard let handle, index >= 0 else { return }
        let clamped = min(1, max(0, value))
        if vmw_parameter_push(handle, UInt32(index), clamped) != 0, let position = parameters.firstIndex(where: { $0.index == index }) {
            parameters[position].value = clamped
        }
    }
    func parameterValue(_ index: Int) -> Float? { parameters.first { $0.index == index }?.value }
    /// Index of the parameter last changed in the plugin's own editor, with a change serial.
    func lastTouchedParameter() -> (index: Int, serial: UInt32)? {
        guard let handle else { return nil }
        var serial: UInt32 = 0
        let index = vmw_touched(handle, &serial)
        return serial == 0 ? nil : (Int(index), serial)
    }
    func needsRelaunch(rate: Double, block: UInt32) -> Bool { self.rate != rate || self.block != block }
    func prepare(rate: Double, block: UInt32) {
        if !needsRelaunch(rate: rate, block: block) { reset(); return }
        refresh(); dispose()
        do { try launch(rate: rate, block: block) } catch { faultMessage = error.localizedDescription }
        reset()
    }
    /// In-place relaunch. Only with the slot outside the render path (stopped IO or tests);
    /// the running mixer replaces the whole slot instead (AudiomeeterEngine.replaceInsert).
    func retry() { refresh(); dispose(); do { try launch(rate: rate, block: block) } catch { faultMessage = error.localizedDescription }; reset() }
    func reset() { if let handle { vmw_reset(handle) }; sideDelay.reset(); mainDelay.reset(); vm_counter_store(alignmentCounter, 0); idle = false }
    func process(_ buffer: UnsafeMutablePointer<Float>, sidechain: UnsafeMutablePointer<Float>?, upstreamLatency: Int, frames: Int, mainDelaySamples: Int = 0, sideDelaySamples: Int? = nil) {
        guard let handle else { return }
        if idle {
            // Resuming after bypass: drop the stale wet block and pre-pause dry history.
            idle = false; vmw_resync(handle); sideDelay.reset(); mainDelay.reset()
        }
        if let sidechain {
            sideBuffer.update(from: sidechain, count: frames*2)
        } else { sideBuffer.update(repeating: 0, count: frames*2) }
        sideDelay.process(sideBuffer, frames: frames, delay: sideDelaySamples ?? upstreamLatency)
        mainDelay.process(buffer, frames: frames, delay: mainDelaySamples)
        vm_counter_store(alignmentCounter, UInt64(max(0, mainDelaySamples)))
        vmw_process(handle, buffer, sideBuffer, Int32(frames))
    }
    func showEditor() { editorRecoveries = 0; requestEditor() }
    func requestSnapshot() { if let handle { snapshotToken = vmw_snapshot(handle) } }
    var snapshotReady: Bool { handle == nil || vmw_snapshot_ack(handle) >= snapshotToken || vmw_fault(handle) != 0 }
    func snapshot() -> InsertConfig { refresh(); return config }
}

@MainActor
final class PluginRuntime {
    static let shared = PluginRuntime()
    let available: Bool
    nonisolated static var workerURL: URL {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/VMPluginWorker.app/Contents/MacOS/VMPluginWorker")
        if FileManager.default.isExecutableFile(atPath: helper.path) { return helper }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/VMPluginWorker")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/plugin-host/VMPluginWorker")
    }
    private init() {
        let candidates = [Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libVMPluginHost.dylib").path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/plugin-host/libVMPluginHost.dylib").path]
        available = FileManager.default.isExecutableFile(atPath: Self.workerURL.path) && candidates.contains { vm_host_load($0) != 0 }
    }
}
