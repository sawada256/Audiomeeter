import Foundation
import Darwin
import VMNative

public enum InsertPosition: String, Codable, CaseIterable { case pre = "PRE", post = "POST" }
public enum InsertTarget: Hashable, Identifiable {
    case bus(BusID), strip(StripID)
    public var id: Int { switch self { case .bus(let bus): return bus.rawValue; case .strip(let strip): return 100 + strip.rawValue } }
    var name: String { switch self { case .bus(let bus): return bus.name; case .strip(let strip): return strip.shortName } }
    static var all: [InsertTarget] { BusID.allCases.map { .bus($0) } + StripID.allCases.map { .strip($0) } }
    static func from(_ id: Int) -> InsertTarget? {
        if id >= 100, let strip = StripID(rawValue: id-100) { return .strip(strip) }
        if let bus = BusID(rawValue: id) { return .bus(bus) }
        return nil
    }
}
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
}

/// Each instance owns a disposable worker process. The mixer never calls plugin code.
final class HostedInsert {
    var config: InsertConfig
    private(set) var position: InsertPosition
    // Bypass is atomic so it can change while audio runs; routing fields need stopped IO.
    private let bypassCounter = vm_counter_create()!
    var bypassed: Bool { vm_counter_load(bypassCounter) != 0 }
    private(set) var sidechain: StripID?
    private(set) var sidechainBus: BusID?
    func updateControls() { position = config.position; setBypassed(config.bypassed); sidechain = config.sidechain; sidechainBus = config.sidechainBus }
    func setBypassed(_ value: Bool) { config.bypassed = value; vm_counter_store(bypassCounter, value ? 1 : 0) }
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
    var needsEditorRecovery: Bool {
        guard let handle, vmw_ready(handle) == 1, let editorRequested else { return false }
        return editorRecoveries < 1 && vmw_editor_ack(handle) < editorToken && Date().timeIntervalSince(editorRequested) > 5
    }
    func recoverEditor() { editorRecoveries += 1; retry(); requestEditor() }
    private func requestEditor() {
        if let handle { editorToken = vmw_editor(handle); editorRequested = Date() }
    }

    init(config: InsertConfig, rate: Double, block: UInt32) throws {
        self.config = config; position = config.position; sidechain = config.sidechain; sidechainBus = config.sidechainBus
        vm_counter_store(bypassCounter, config.bypassed ? 1 : 0)
        sideBuffer.initialize(repeating: 0, count: 8192)
        do { try launch(rate: rate, block: block) } catch { dispose(); sideBuffer.deallocate(); vm_counter_destroy(alignmentCounter); vm_counter_destroy(bypassCounter); throw error }
    }
    deinit { dispose(); sideBuffer.deallocate(); vm_counter_destroy(alignmentCounter); vm_counter_destroy(bypassCounter) }
    private func launch(rate: Double, block: UInt32) throws {
        self.rate = rate; self.block = block; faultMessage = nil; started = Date()
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
    }
    private func dispose() {
        editorRequested = nil; editorToken = 0
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
        if vmw_ready(handle) == 2 { faultMessage = faultMessage ?? L10n.text("プラグインを読み込めませんでした"); vmw_set_fault(handle, 1) }
        if let worker, !worker.isRunning { faultMessage = faultMessage ?? L10n.text("プラグインが終了しました（遅延を保ってバイパス中）"); vmw_set_fault(handle, 2) }
        if vmw_ready(handle) == 0 && Date().timeIntervalSince(started) > 15 { faultMessage = L10n.text("プラグインの読込がタイムアウトしました"); vmw_set_fault(handle, 3) }
        if vmw_fault(handle) != 0, let worker, worker.isRunning { kill(worker.processIdentifier, SIGKILL) }
        config.savedLatency = max(0, latency - Int(block))
    }
    func needsRelaunch(rate: Double, block: UInt32) -> Bool { self.rate != rate || self.block != block }
    func prepare(rate: Double, block: UInt32) {
        if !needsRelaunch(rate: rate, block: block) { reset(); return }
        refresh(); dispose()
        do { try launch(rate: rate, block: block) } catch { faultMessage = error.localizedDescription }
        reset()
    }
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
