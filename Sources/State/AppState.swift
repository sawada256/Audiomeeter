import Foundation
import SwiftUI
import CoreAudio
import Combine
import VMNative
import ServiceManagement

/// Observable application state bridging UI and real-time AudiomeeterEngine
@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // Available devices on the Mac
    @Published public var inputDevices: [AudioDeviceInfo] = []
    @Published public var outputDevices: [AudioDeviceInfo] = []

    // Strip Settings
    @Published public var strips: [StripID: StripSettings] = [:]
    // Bus Settings
    @Published public var buses: [BusID: BusSettings] = [:]

    @Published public var eqPresets: [Int: [MasterEQConfig?]] = [:]
    @Published public var stripEQPresets: [Int: [EQ3Band?]] = [:]

    // Meter readings (0...1 normalized for UI display)
    let meterStore = MixerMeterStore()
    public var stripMeters: [StripID: MeterLevel] {
        get { meterStore.frame.strips }
        set { meterStore.frame.strips = newValue }
    }
    public var busMeters: [BusID: MeterLevel] {
        get { meterStore.frame.buses }
        set { meterStore.frame.buses = newValue }
    }

    // Engine status
    @Published public var isStartingAudio = false
    @Published public var isEngineRunning: Bool = false
    @Published public var engineSampleRate: Double = 48000.0
    @Published public var engineBufferSize: UInt32 = 256
    @Published public var masterA1DeviceName: String = "Select A1 Master Device"

    public let recorderPlayer = AudioRecorderPlayer()

    // Per-Application Volume Lists (Potato feature)
    @Published public var vaioAppVolumes: [AppVolumeItem] = []
    @Published public var auxAppVolumes: [AppVolumeItem] = []

    @Published public var audioError: String?
    @Published public var insertConfigs: [InsertTarget: [InsertConfig]] = [:]
    @Published var desktopControls = DesktopControlsPreferences()
    @Published var desktopControlsStatus = ""
    @Published var systemOutputStrip: StripID?
    @Published var insertChainEnabled: [Int: Bool] = [:]
    func setDesktopControls(_ preferences: DesktopControlsPreferences) {
        var value = preferences; value.normalize(); desktopControls = value; saveSettings()
    }
    func insertChainIsEnabled(_ target: InsertTarget) -> Bool { insertChainEnabled[target.id] ?? true }
    func toggleInsertChain(_ target: InsertTarget) {
        let enabled = !insertChainIsEnabled(target)
        engine.withStoppedAudio {
            if enabled { engine.disabledInsertTargets.remove(target) } else { engine.disabledInsertTargets.insert(target) }
        }
        insertChainEnabled[target.id] = enabled; updateInsertLatency(); saveSettings()
    }
    func applyHotkey(target id: Int, action: MixerHotkeyAction) {
        guard let target = InsertTarget.from(id), !isStartingAudio else { return }
        let step = Float(desktopControls.gainStep) * (action == .decrease ? -1 : 1)
        switch target {
        case .strip(let strip):
            if action == .mute { toggleStripMute(strip: strip) }
            else { setStripGain(strip: strip, gainDB: min(12, max(-60, (strips[strip]?.gainDB ?? 0) + step))) }
        case .bus(let bus):
            if action == .mute { toggleBusMute(bus: bus) }
            else { setBusGain(bus: bus, gainDB: min(12, max(-60, (buses[bus]?.gainDB ?? 0) + step))) }
        }
    }
    @Published public var insertLatencies: [InsertTarget: Int] = [:]
    @Published public var appTrimSupported: [StripID: Bool] = [:]
    @Published public var appTrimErrors: [StripID: String] = [:]
    @Published public var meterRefreshRate: Double = 30
    @Published public var preferredBuffer: UInt32?
    @Published public var preferredRate: Double?
    public var pluginHostingAvailable: Bool { PluginRuntime.shared.available }
    private var saveWork: DispatchWorkItem?
    private let isUIPreview = ProcessInfo.processInfo.arguments.contains("--ui-preview") || Bundle.main.bundleIdentifier == "local.audiomeeter.uipreview"
    private var savedAppTrims: [String: Float] = [:]

    private var meterTimer: Timer?
    @Published public var insertStatus: [UUID: String] = [:]
    @Published public var insertSideChannels: [UUID: Int] = [:]
    @Published public var latencyCompensationEnabled = true
    @Published public var outputBusAlignmentEnabled = true
    @Published public var sidechainAlignmentEnabled = true
    @Published public var insertAlignmentDelays: [UUID: Int] = [:]
    @Published public var routeCompensation: [InsertTarget: Int] = [:]
    public func setLatencyCompensation(_ enabled: Bool) {
        engine.withStoppedAudio { engine.latencyCompensationEnabled = enabled }
        latencyCompensationEnabled = enabled; saveSettings()
    }
    public func setSidechainAlignment(_ enabled: Bool) {
        engine.withStoppedAudio { engine.sidechainAlignmentEnabled = enabled }
        sidechainAlignmentEnabled = enabled; saveSettings()
    }
    public func setOutputBusAlignment(_ enabled: Bool) {
        engine.withStoppedAudio { engine.outputBusAlignmentEnabled = enabled }
        outputBusAlignmentEnabled = enabled; saveSettings()
    }
    public func sidechainUsesPreviousBlock(target: InsertTarget, bus: BusID) -> Bool {
        SidechainRenderGraph(strips: strips, inserts: insertConfigs.filter { insertChainIsEnabled($0.key) }).usesPreviousBlock(source: bus, target: target)
    }
    public func sidechainAlignmentSamples(target: InsertTarget) -> Int {
        insertChainIsEnabled(target) ? (insertConfigs[target] ?? []).filter { !$0.bypassed }.reduce(0) { $0 + (insertAlignmentDelays[$1.id] ?? 0) } : 0
    }
    @Published public var automaticDeviceRestart = true
    @Published public var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published public var loginApprovalRequired = SMAppService.mainApp.status == .requiresApproval
    private var lastHeartbeat: UInt64 = 0
    private var lastAudioProgress = Date()
    private var lastAutoRestart = Date.distantPast
    public func setAutomaticDeviceRestart(_ enabled: Bool) {
        automaticDeviceRestart = enabled; lastAudioProgress = Date(); saveSettings()
        if enabled { refreshDevices() }
    }
    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { audioError = L10n.text("ログイン時の自動起動設定に失敗しました: {0}", [String(describing: error.localizedDescription)]) }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loginApprovalRequired = SMAppService.mainApp.status == .requiresApproval
    }
    public func setStripPan(strip: StripID, pan: Float) {
        guard pan.isFinite else { return }
        let value = StereoPanControl.normalized(pan)
        strips[strip]?.pan = value; engine.updateStripSettings(strip: strip) { $0.pan = value }; saveSettings()
    }
    private func checkAudioRecovery() {
        guard automaticDeviceRestart, !isStartingAudio, !isUIPreview, engine.isRunning else { lastAudioProgress = Date(); return }
        let heartbeat = engine.renderHeartbeat
        if heartbeat != lastHeartbeat { lastHeartbeat = heartbeat; lastAudioProgress = Date(); return }
        if Date().timeIntervalSince(lastAudioProgress) > 3 && Date().timeIntervalSince(lastAutoRestart) > 10 {
            lastAutoRestart = Date(); lastAudioProgress = Date()
            deviceManager.refreshDevices(); refreshDevices()
            engine.restartEngine(); reportDeviceErrors()
        }
    }
    private var appPollTimer: Timer?
    private let engine = AudiomeeterEngine.shared
    private let deviceManager = AudioDeviceManager.shared

    public init() {
        // Link recorder to engine
        engine.recorderPlayer = recorderPlayer

        // Initialize default strip and bus settings
        for strip in StripID.allCases {
            strips[strip] = StripSettings(
                routing: RoutingMatrix(a1: true, b1: strip.isHardware)
            )
            stripMeters[strip] = MeterLevel()
        }

        for bus in BusID.allCases {
            buses[bus] = BusSettings()
            busMeters[bus] = MeterLevel()
        }

        // Load saved settings if any
        loadSettings()

        // Setup device manager callback
        deviceManager.onDevicesChanged = { [weak self] _ in
            Task { @MainActor in
                self?.refreshDevices()
            }
        }
        refreshDevices()

        // Reconnect all saved devices from previous session
        if !isUIPreview { reconnectSavedDevices() }

        // Automatically assign virtual devices (BlackHole / Audiomeeter) if still unassigned
        if !isUIPreview { autoAssignVirtualDevices() }

        if !isUIPreview, let frames = preferredBuffer {
            do { try engine.configureClock(rate: preferredRate, frames: frames) }
            catch { audioError = error.localizedDescription }
        }
        if !isUIPreview { restoreInserts() }

        // HAL startup can wait for a driver. Keep the window responsive while
        // starting and prohibit graph changes until the start operation completes.
        if isUIPreview {
            startMeterPolling()
            startAppPolling()
        } else {
            isStartingAudio = true
            let startup = DispatchWorkItem { [weak self, engine] in
                engine.start()
                Task { @MainActor in
                    guard let self else { return }
                    self.isStartingAudio = false
                    self.isEngineRunning = self.engine.isRunning
                    self.engineSampleRate = self.engine.engineSampleRate
                    self.engineBufferSize = self.engine.bufferSize
                    self.refreshDevices()
                    self.reportDeviceErrors()
                    self.startMeterPolling()
                    self.startAppPolling()
                }
            }
            DispatchQueue.global(qos: .userInitiated).async(execute: startup)
        }
    }

    public func refreshDevices() {
        self.inputDevices = deviceManager.getInputDevices()
        self.outputDevices = deviceManager.getOutputDevices()
        if !isStartingAudio && !isUIPreview {
            if recorderPlayer.isRecording,
               let uid = buses[.A1]?.deviceUID,
               let device = outputDevices.first(where: { $0.uid == uid }),
               abs(device.sampleRate - engine.engineSampleRate) >= 1 {
                recorderPlayer.stopRecording()
                audioError = L10n.text("マスターデバイスのサンプルレートが変更されたため、録音を終了しました。")
            }
            if automaticDeviceRestart { engine.reconcileDevices(deviceManager.devices) }
        }
        engineSampleRate = engine.engineSampleRate
        engineBufferSize = engine.bufferSize
    }

    private func reconnectSavedDevices() {
        // Sanitize legacy incorrect bus assignments
        if buses[.B1]?.deviceUID == "Audiomeeter_UID" {
            buses[.B1]?.deviceUID = nil
        }
        if buses[.B2]?.deviceUID == "AudiomeeterAUX_UID" {
            buses[.B2]?.deviceUID = nil
        }

        for (strip, setting) in strips {
            if let uid = setting.deviceUID, let dev = inputDevices.first(where: { $0.uid == uid }) {
                setStripDevice(strip: strip, device: dev)
            }
        }
        for (bus, setting) in buses {
            if let uid = setting.deviceUID, let dev = outputDevices.first(where: { $0.uid == uid }) {
                setBusDevice(bus: bus, device: dev)
            }
        }
    }

    private func autoAssignVirtualDevices() {
        // 1. Virtual Input 1 (VAIO): Audiomeeter VAIO, Audiomeeter, or BlackHole 2ch
        if let vaio = inputDevices.first(where: { $0.name == "Voicemeeter" || $0.name == "Voicemeeter VAIO" || $0.name == "Audiomeeter" || $0.name == "Audiomeeter VAIO" || $0.name == "BlackHole 2ch" }) {
            if strips[.virtualVAIO]?.deviceUID == nil {
                setStripDevice(strip: .virtualVAIO, device: vaio)
            }
        }

        // 2. Virtual Input 2 (AUX): Audiomeeter AUX or BlackHole 16ch
        if let aux = inputDevices.first(where: { $0.name == "Voicemeeter AUX" || $0.name == "Audiomeeter AUX" || $0.name.contains("BlackHole 16ch") }) {
            if strips[.virtualAUX]?.deviceUID == nil {
                setStripDevice(strip: .virtualAUX, device: aux)
            }
        }

        // 3. Virtual Output B1 (VAIO Out): Audiomeeter B1 ONLY (never assign to Audiomeeter playback!)
        if let outB1 = outputDevices.first(where: { ["AudiomeeterB1_UID", "VoicemeeterB1_UID"].contains($0.uid) }) {
            if buses[.B1]?.deviceUID == nil {
                setBusDevice(bus: .B1, device: outB1)
            }
        }

        // 4. Virtual Output B2 (AUX Out): Audiomeeter B2 ONLY (never assign to Audiomeeter AUX playback!)
        if let outB2 = outputDevices.first(where: { ["AudiomeeterB2_UID", "VoicemeeterB2_UID"].contains($0.uid) }) {
            if buses[.B2]?.deviceUID == nil {
                setBusDevice(bus: .B2, device: outB2)
            }
        }


        // 5. Default Output for A1 (Master Clock)
        if buses[.A1]?.deviceUID == nil {
            if let defOut = outputDevices.first(where: { $0.isDefaultOutput && !$0.name.contains("BlackHole") && !$0.name.contains("Audiomeeter") }) {
                setBusDevice(bus: .A1, device: defOut)
            } else if let nonVirtualOut = outputDevices.first(where: { !$0.name.contains("BlackHole") && !$0.name.contains("Audiomeeter") && $0.outChannels > 0 }) {
                setBusDevice(bus: .A1, device: nonVirtualOut)
            }
        }

        // 6. Default Hardware 1 to default input mic if unset
        if strips[.hardware1]?.deviceUID == nil {
            if let defIn = inputDevices.first(where: { $0.isDefaultInput && !$0.name.contains("BlackHole") && !$0.name.contains("Audiomeeter") }) {
                setStripDevice(strip: .hardware1, device: defIn)
            }
        }
    }

    // MARK: - Device Assignment

    public func setStripDevice(strip: StripID, device: AudioDeviceInfo?) {
        guard !isStartingAudio else { return }
        strips[strip]?.deviceUID = device?.uid
        if let source = InternalBusRouting.source(device?.uid) {
            strips[strip]?.routing[source] = false
            if InternalBusRouting.hasCycle(strips) {
                strips[strip]?.routing[.B1] = false; strips[strip]?.routing[.B2] = false
            }
            if let routing = strips[strip]?.routing { engine.updateStripSettings(strip: strip) { $0.routing = routing } }
        }
        engine.assignInputDevice(strip: strip, device: device)
        reportDeviceErrors()
        saveSettings()
    }

    public func setBusDevice(bus: BusID, device: AudioDeviceInfo?) {
        guard !isStartingAudio else { return }
        if bus == .A1, recorderPlayer.isRecording, let device, abs(device.sampleRate - engine.engineSampleRate) >= 1 {
            audioError = L10n.text("録音中は異なるサンプルレートのマスターへ切り替えできません。")
            return
        }
        buses[bus]?.deviceUID = device?.uid
        if bus == .A1 {
            masterA1DeviceName = device?.name ?? "Select A1 Master Device"
            engineSampleRate = device?.sampleRate ?? 48000.0
        }
        engine.assignOutputDevice(bus: bus, device: device)
        engineSampleRate = engine.engineSampleRate
        engineBufferSize = engine.bufferSize
        reportDeviceErrors()
        saveSettings()
    }

    // MARK: - Strip Controls

    public func setStripChannels(strip: StripID, offset: Int) {
        guard !isStartingAudio else { return }
        strips[strip]?.channelOffset = offset
        strips[strip]?.leftChannel = nil; strips[strip]?.rightChannel = nil
        engine.updateStripSettings(strip: strip) { $0.channelOffset = offset; $0.leftChannel = nil; $0.rightChannel = nil }
        let device = inputDevices.first { $0.uid == strips[strip]?.deviceUID }
        engine.assignInputDevice(strip: strip, device: device)
        reportDeviceErrors()
        saveSettings()
    }

    public func setBusChannels(bus: BusID, offset: Int) {
        guard !isStartingAudio else { return }
        buses[bus]?.channelOffset = offset
        buses[bus]?.leftChannel = nil; buses[bus]?.rightChannel = nil
        engine.updateBusSettings(bus: bus) { $0.channelOffset = offset; $0.leftChannel = nil; $0.rightChannel = nil }
        let device = outputDevices.first { $0.uid == buses[bus]?.deviceUID }
        engine.assignOutputDevice(bus: bus, device: device)
        saveSettings()
    }

    public func setStripChannel(strip: StripID, left: Bool, channel: Int) {
        guard !isStartingAudio, let device = inputDevices.first(where: { $0.uid == strips[strip]?.deviceUID }), channel >= 0, channel < device.inChannels else { return }
        if left { strips[strip]?.leftChannel = channel } else { strips[strip]?.rightChannel = channel }
        let settings = strips[strip]!
        engine.updateStripSettings(strip: strip) { $0.leftChannel = settings.leftChannel; $0.rightChannel = settings.rightChannel }
        engine.assignInputDevice(strip: strip, device: device)
        reportDeviceErrors()
        saveSettings()
    }

    public func setBusChannel(bus: BusID, left: Bool, channel: Int) {
        guard !isStartingAudio, let device = outputDevices.first(where: { $0.uid == buses[bus]?.deviceUID }), channel >= 0, channel < device.outChannels else { return }
        if left { buses[bus]?.leftChannel = channel } else { buses[bus]?.rightChannel = channel }
        let settings = buses[bus]!
        engine.updateBusSettings(bus: bus) { $0.leftChannel = settings.leftChannel; $0.rightChannel = settings.rightChannel }
        engine.assignOutputDevice(bus: bus, device: device)
        reportDeviceErrors()
        saveSettings()
    }

    public func setStripGain(strip: StripID, gainDB: Float) {
        strips[strip]?.gainDB = gainDB
        engine.updateStripSettings(strip: strip) { $0.gainDB = gainDB }
        saveSettings()
    }

    public func toggleStripMute(strip: StripID) {
        guard var s = strips[strip] else { return }
        s.isMuted.toggle()
        strips[strip] = s
        engine.updateStripSettings(strip: strip) { $0.isMuted = s.isMuted }
        saveSettings()
    }

    public func toggleStripSolo(strip: StripID) {
        guard var s = strips[strip] else { return }
        s.isSolo.toggle()
        strips[strip] = s
        engine.updateStripSettings(strip: strip) { $0.isSolo = s.isSolo }
        saveSettings()
    }

    public func toggleRouting(strip: StripID, bus: BusID) {
        guard var s = strips[strip] else { return }
        s.routing[bus].toggle()
        var candidate = strips; candidate[strip] = s
        guard !InternalBusRouting.hasCycle(candidate) else {
            audioError = L10n.text("内部バスへ戻す経路が循環するため、このルーティングは有効にできません。"); return
        }
        strips[strip] = s
        engine.updateStripSettings(strip: strip) { $0.routing[bus] = s.routing[bus] }
        saveSettings()
    }

    public func setStripIntellipan(strip: StripID, x: Float, y: Float) {
        strips[strip]?.intellipan = IntellipanState(x: x, y: y)
        engine.updateStripSettings(strip: strip) { $0.intellipan = IntellipanState(x: x, y: y) }
        saveSettings()
    }

    public func setStripDynamics(strip: StripID, comp: Float? = nil, gate: Float? = nil) {
        guard var s = strips[strip] else { return }
        if let c = comp { s.dynamics.compKnob = c }
        if let g = gate { s.dynamics.gateKnob = g }
        strips[strip] = s
        engine.updateStripSettings(strip: strip) { $0.dynamics = s.dynamics }
        saveSettings()
    }

    public func setStripEQ(strip: StripID, low: Float? = nil, mid: Float? = nil, high: Float? = nil) {
        guard var s = strips[strip] else { return }
        if let l = low { s.eq.lowGainDB = l }
        if let m = mid { s.eq.midGainDB = m }
        if let h = high { s.eq.highGainDB = h }
        strips[strip] = s
        engine.updateStripSettings(strip: strip) { $0.eq = s.eq }
        saveSettings()
    }

    // MARK: - Bus Controls

    public func setBusGain(bus: BusID, gainDB: Float) {
        buses[bus]?.gainDB = gainDB
        engine.updateBusSettings(bus: bus) { $0.gainDB = gainDB }
        saveSettings()
    }

    public func toggleBusMute(bus: BusID) {
        guard var b = buses[bus] else { return }
        b.isMuted.toggle()
        buses[bus] = b
        engine.updateBusSettings(bus: bus) { $0.isMuted = b.isMuted }
        saveSettings()
    }

    public func toggleStripKaraoke(strip: StripID) {
        guard var s = strips[strip] else { return }
        s.isKaraoke.toggle()
        strips[strip] = s
        engine.updateStripSettings(strip: strip) { $0.isKaraoke = s.isKaraoke }
        saveSettings()
    }

    public func setBusLimiter(bus: BusID, enabled: Bool) {
        buses[bus]?.isLimiterEnabled = enabled
        engine.updateBusSettings(bus: bus) { $0.isLimiterEnabled = enabled }
        saveSettings()
    }

    public func setBusMode(bus: BusID, mode: BusMode) {
        buses[bus]?.mode = mode
        engine.updateBusSettings(bus: bus) { $0.mode = mode }
        saveSettings()
    }

    // MARK: - Bus EQ Controls (Left click toggle, Right click configure)

    public func toggleBusEQ(bus: BusID) {
        guard var b = buses[bus] else { return }
        b.isEQEnabled.toggle()
        b.eqConfig.isEnabled = b.isEQEnabled
        buses[bus] = b
        engine.updateBusSettings(bus: bus) {
            $0.isEQEnabled = b.isEQEnabled
            $0.eqConfig.isEnabled = b.isEQEnabled
        }
        saveSettings()
    }

    public func setBusEQConfig(bus: BusID, config: MasterEQConfig) {
        guard var b = buses[bus] else { return }
        b.eqConfig = config
        b.isEQEnabled = config.isEnabled
        buses[bus] = b
        engine.updateBusSettings(bus: bus) {
            $0.eqConfig = config
            $0.isEQEnabled = config.isEnabled
        }
        saveSettings()
    }

    public func setBusEQBand(bus: BusID, bandIndex: Int, type: FilterType? = nil, freqHz: Float? = nil, gainDB: Float? = nil, q: Float? = nil, isEnabled: Bool? = nil) {
        guard var b = buses[bus], bandIndex >= 0, bandIndex < b.eqConfig.bands.count else { return }
        if let t = type { b.eqConfig.bands[bandIndex].type = t }
        if let f = freqHz { b.eqConfig.bands[bandIndex].freqHz = f }
        if let g = gainDB { b.eqConfig.bands[bandIndex].gainDB = g }
        if let qVal = q { b.eqConfig.bands[bandIndex].q = qVal }
        if let en = isEnabled { b.eqConfig.bands[bandIndex].isEnabled = en }
        buses[bus] = b
        engine.updateBusSettings(bus: bus) { $0.eqConfig = b.eqConfig }
        saveSettings()
    }

    public func resetBusEQ(bus: BusID) {
        setBusEQConfig(bus: bus, config: MasterEQConfig(isEnabled: buses[bus]?.isEQEnabled ?? false))
    }

    private func reportDeviceErrors() {
        if !engine.deviceErrors.isEmpty { audioError = engine.deviceErrors.joined(separator: "\n") }
    }

    public func restartAudioEngine() {
        guard !isStartingAudio else { return }
        engine.restartEngine()
        isEngineRunning = engine.isRunning
        reportDeviceErrors()
    }

    // MARK: - Meter & Transport Polling (Smooth 60 FPS)

    private func startMeterPolling() {
        let timer = Timer(timeInterval: 1.0 / meterRefreshRate, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.meterStore.frame = MixerMeterStore.Frame(
                    strips: Dictionary(uniqueKeysWithValues: StripID.allCases.map { ($0, self.engine.getStripMeter(strip: $0)) }),
                    buses: Dictionary(uniqueKeysWithValues: BusID.allCases.map { ($0, self.engine.getBusMeter(bus: $0)) }))
                // Update tape recorder/player time
                self.recorderPlayer.updatePlaybackTime()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.meterTimer = timer
    }

    public func saveStripEQPreset(strip: StripID, slot: Int) {
        guard (0..<3).contains(slot), let config = strips[strip]?.eq else { return }
        var presets = stripEQPresets[strip.rawValue] ?? [nil, nil, nil]
        while presets.count < 3 { presets.append(nil) }
        presets[slot] = config; stripEQPresets[strip.rawValue] = presets; saveSettings()
    }

    public func loadStripEQPreset(strip: StripID, slot: Int) {
        guard let presets = stripEQPresets[strip.rawValue], presets.indices.contains(slot), let config = presets[slot] else { return }
        strips[strip]?.eq = config
        engine.updateStripSettings(strip: strip) { $0.eq = config }
        saveSettings()
    }

    public func saveEQPreset(bus: BusID, slot: Int) {
        guard (0..<3).contains(slot), let config = buses[bus]?.eqConfig else { return }
        var presets = eqPresets[bus.rawValue] ?? [nil, nil, nil]
        while presets.count < 3 { presets.append(nil) }
        presets[slot] = config
        eqPresets[bus.rawValue] = presets
        saveSettings()
    }

    public func loadEQPreset(bus: BusID, slot: Int) {
        guard let presets = eqPresets[bus.rawValue], presets.indices.contains(slot), let config = presets[slot] else { return }
        setBusEQConfig(bus: bus, config: config)
    }

    // MARK: - Persistence

    private struct AppConfig: Codable {
        var strips: [Int: StripSettings]
        var buses: [Int: BusSettings]
        var inserts: [Int: [InsertConfig]]?
        var buffer: UInt32?
        var rate: Double?
        var meterRate: Double?
        var appTrims: [String: Float]?
        var latencyCompensation: Bool?
        var outputBusAlignment: Bool?
        var sidechainAlignment: Bool?
        var eqPresets: [Int: [MasterEQConfig?]]?
        var stripEQPresets: [Int: [EQ3Band?]]?
        var automaticDeviceRestart: Bool?
        var desktopControls: DesktopControlsPreferences?
        var insertChainEnabled: [Int: Bool]?
    }

    private var settingsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Audiomeeter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    private func saveSettings() {
        guard !isUIPreview else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeSettings() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func writeSettings() {
        guard !isUIPreview else { return }
        var rawStrips: [Int: StripSettings] = [:]
        for (k, v) in strips { rawStrips[k.rawValue] = v }
        var rawBuses: [Int: BusSettings] = [:]
        for (k, v) in buses { rawBuses[k.rawValue] = v }

        let config = AppConfig(strips: rawStrips, buses: rawBuses, inserts: Dictionary(uniqueKeysWithValues: insertConfigs.map { ($0.key.id, $0.value) }), buffer: preferredBuffer, rate: preferredRate, meterRate: meterRefreshRate, appTrims: savedAppTrims, latencyCompensation: latencyCompensationEnabled, sidechainAlignment: sidechainAlignmentEnabled, eqPresets: eqPresets, stripEQPresets: stripEQPresets, automaticDeviceRestart: automaticDeviceRestart)
        var savedConfig = config
        savedConfig.outputBusAlignment = outputBusAlignmentEnabled
        savedConfig.desktopControls = desktopControls; savedConfig.insertChainEnabled = insertChainEnabled
        if let data = try? JSONEncoder().encode(savedConfig) {
            try? data.write(to: settingsFileURL, options: .atomic)
        }
    }

    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsFileURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else { return }

        automaticDeviceRestart = config.automaticDeviceRestart ?? true
        desktopControls = config.desktopControls ?? DesktopControlsPreferences(); desktopControls.normalize()
        insertChainEnabled = config.insertChainEnabled ?? [:]
        engine.disabledInsertTargets = Set(insertChainEnabled.filter { !$0.value }.compactMap { InsertTarget.from($0.key) })
        eqPresets = config.eqPresets ?? [:]
        stripEQPresets = config.stripEQPresets ?? [:]
        latencyCompensationEnabled = config.latencyCompensation ?? true
        engine.latencyCompensationEnabled = latencyCompensationEnabled
        outputBusAlignmentEnabled = config.outputBusAlignment ?? latencyCompensationEnabled
        engine.outputBusAlignmentEnabled = outputBusAlignmentEnabled
        sidechainAlignmentEnabled = config.sidechainAlignment ?? true
        engine.sidechainAlignmentEnabled = sidechainAlignmentEnabled
        preferredBuffer = config.buffer
        preferredRate = config.rate
        meterRefreshRate = [15.0, 30.0, 60.0].contains(config.meterRate ?? 30) ? (config.meterRate ?? 30) : 30
        savedAppTrims = config.appTrims ?? [:]
        for (key, slots) in config.inserts ?? [:] {
            if let target = InsertTarget.from(key) { insertConfigs[target] = slots }
        }
        for (k, v) in config.strips {
            if let strip = StripID(rawValue: k) {
                strips[strip] = v
                engine.updateStripSettings(strip: strip) { $0 = v }
            }
        }
        for (k, v) in config.buses {
            if let bus = BusID(rawValue: k) {
                buses[bus] = v
                engine.updateBusSettings(bus: bus) { $0 = v }
            }
        }
    }
}

@MainActor
extension AppState {
    public func applyAudioSettings(rate: Double, frames: UInt32, meters: Double) {
        guard !isStartingAudio else { return }
        guard !recorderPlayer.isRecording else { audioError = L10n.text("録音中はオーディオ設定を変更できません。"); return }
        do {
            try engine.configureClock(rate: rate, frames: frames)
            preferredRate = rate
            preferredBuffer = frames
            engineSampleRate = engine.engineSampleRate
            engineBufferSize = engine.bufferSize
            meterRefreshRate = meters
            meterTimer?.invalidate()
            startMeterPolling()
            saveSettings()
        } catch {
            engineSampleRate = engine.engineSampleRate
            engineBufferSize = engine.bufferSize
            audioError = error.localizedDescription
        }
    }

    public func rescanDevices() { deviceManager.refreshDevices() }

    private func restoreInserts() {
        guard pluginHostingAvailable else { return }
        for target in InsertTarget.all {
            for config in insertConfigs[target] ?? [] {
                do {
                    let slot = try HostedInsert(config: config, rate: engine.engineSampleRate, block: engine.bufferSize)
                    engine.inserts[target, default: []].append(slot)
                } catch { audioError = "\(config.name): \(error.localizedDescription)" }
            }
        }
        updateInsertLatency()
    }

    public func addInsert(target: InsertTarget, position: InsertPosition, path: String, identifier: String? = nil) {
        guard !isStartingAudio else { return }
        guard pluginHostingAvailable else { audioError = L10n.text("VST3ホストが見つかりません。build_app.shでアプリをビルドしてください。"); return }
        engine.withStoppedAudio {
            do {
                var config = InsertConfig(path: path, name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, position: position)
                config.identifier = identifier
                let slot = try HostedInsert(config: config, rate: engine.engineSampleRate, block: engine.bufferSize)
                engine.inserts[target, default: []].append(slot)
                insertConfigs[target, default: []].append(slot.snapshot())
            } catch { audioError = error.localizedDescription }
        }
        updateInsertLatency()
        saveSettings()
    }

    public func editInsert(target: InsertTarget, id: UUID) {
        guard let slot = engine.inserts[target]?.first(where: { $0.config.id == id }) else { return }
        slot.refresh()
        if !slot.status.isEmpty && slot.status != L10n.text("読込中…") { engine.withStoppedAudio { slot.retry() } }
        slot.showEditor()
    }

    public func changeInsert(target: InsertTarget, id: UUID, remove: Bool = false, move: Int = 0, bypass: Bool? = nil) {
        guard !isStartingAudio else { return }
        engine.withStoppedAudio {
            guard var configs = insertConfigs[target], let index = configs.firstIndex(where: { $0.id == id }) else { return }
            if remove {
                configs.remove(at: index)
                engine.inserts[target]?.removeAll { $0.config.id == id }
            } else if let bypass {
                configs[index].bypassed = bypass
                engine.inserts[target]?.first(where: { $0.config.id == id })?.config.bypassed = bypass
                engine.inserts[target]?.first(where: { $0.config.id == id })?.updateControls()
            } else if move != 0 {
                let next = index + move
                if configs.indices.contains(next), configs[next].position == configs[index].position {
                    configs.swapAt(index, next)
                    engine.inserts[target]?.sort { a, b in configs.firstIndex(where: { $0.id == a.config.id })! < configs.firstIndex(where: { $0.id == b.config.id })! }
                }
            }
            insertConfigs[target] = configs
        }
        updateInsertLatency()
        saveSettings()
    }

    private func updateInsertLatency() {
        for target in InsertTarget.all {
            insertLatencies[target] = engine.insertLatency(target)
            routeCompensation[target] = engine.compensationSamples(target: target)
            for slot in engine.inserts[target] ?? [] { insertAlignmentDelays[slot.config.id] = slot.alignmentDelaySamples }
        }
    }
    public func setInsertSidechain(target: InsertTarget, id: UUID, strip: StripID?, bus: BusID? = nil) {
        engine.withStoppedAudio {
            if let slot = engine.inserts[target]?.first(where: { $0.config.id == id }) {
                slot.config.sidechain = strip; slot.config.sidechainBus = bus; slot.updateControls()
                if let index = insertConfigs[target]?.firstIndex(where: { $0.id == id }) { insertConfigs[target]?[index].sidechain = strip; insertConfigs[target]?[index].sidechainBus = bus }
            }
        }
        saveSettings()
    }
    public func retryInsert(target: InsertTarget, id: UUID) {
        engine.withStoppedAudio { engine.inserts[target]?.first(where: { $0.config.id == id })?.retry() }
        refreshPlugins()
    }
    private func refreshPlugins() {
        var changed = false
        for target in InsertTarget.all {
            for slot in engine.inserts[target] ?? [] {
                if slot.needsEditorRecovery { engine.withStoppedAudio { slot.recoverEditor() } }
                slot.refresh(); insertStatus[slot.config.id] = slot.status
                insertSideChannels[slot.config.id] = slot.sidechainChannels
                if let index = insertConfigs[target]?.firstIndex(where: { $0.id == slot.config.id }), insertConfigs[target]?[index] != slot.config {
                    insertConfigs[target]?[index] = slot.config; changed = true
                }
            }
        }
        updateInsertLatency()
        if changed { saveSettings() }
    }

    public func capturePluginStates() { Task { @MainActor in await snapshotPlugins() } }
    public func snapshotPlugins() async {
        let slots = engine.inserts.values.flatMap { $0 }
        for slot in slots { slot.requestSnapshot() }
        for _ in 0..<10 {
            if slots.allSatisfy({ $0.snapshotReady }) { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        refreshPlugins(); saveWork?.cancel(); writeSettings()
    }
    public func setBusDelay(bus: BusID, milliseconds: Double) {
        guard milliseconds.isFinite else { return }
        let value = min(500, max(0, milliseconds))
        buses[bus]?.delayMilliseconds = value
        engine.updateBusSettings(bus: bus) { $0.delayMilliseconds = value }
        saveSettings()
    }
    public func compensationSamples(target: InsertTarget) -> Int {
        routeCompensation[target] ?? 0
    }

    public func shutdown() {
        if isStartingAudio { saveWork?.cancel(); writeSettings(); return }
        engine.stop()
        recorderPlayer.stopRecording()
        refreshPlugins()
        saveWork?.cancel()
        writeSettings()
        meterTimer?.invalidate()
        appPollTimer?.invalidate()
    }

    private func startAppPolling() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollAppVolumes(); self?.refreshPlugins(); self?.checkAudioRecovery() }
        }
        RunLoop.main.add(timer, forMode: .common)
        appPollTimer = timer
        pollAppVolumes()
    }

    private func pollAppVolumes() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var defaultID: AudioObjectID = 0, size = UInt32(MemoryLayout<AudioObjectID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultID) == noErr {
            let uid = deviceManager.findDevice(byID: defaultID)?.uid
            let selected: StripID? = ["Audiomeeter_UID", "Voicemeeter_UID"].contains(uid) ? .virtualVAIO : ["AudiomeeterAUX_UID", "VoicemeeterAUX_UID"].contains(uid) ? .virtualAUX : nil
            if systemOutputStrip != selected { systemOutputStrip = selected }
        }
        for strip in [StripID.virtualVAIO, .virtualAUX] {
            var items: [AppVolumeItem] = []
            var supported = false
            if let uid = strips[strip]?.deviceUID, let device = inputDevices.first(where: { $0.uid == uid }) {
                do {
                    let values = try AppTrimTransport.read(device.id)
                    supported = true
                    appTrimErrors[strip] = nil
                    var seen: Set<Int32> = []
                    for value in values where value.pid > 0 && value.pid != ProcessInfo.processInfo.processIdentifier {
                        guard seen.insert(value.pid).inserted else { continue }
                        let app = NSRunningApplication(processIdentifier: value.pid)
                        var gain = value.gain
                        if let bundle = app?.bundleIdentifier, let saved = savedAppTrims["\(strip.rawValue):\(bundle)"], abs(saved - gain) > 0.001 {
                            if AppTrimTransport.set(device.id, pid: value.pid, gain: saved) == noErr { gain = saved }
                        }
                        items.append(AppVolumeItem(pid: value.pid, name: app?.localizedName ?? "Process \(value.pid)", volume: gain))
                    }
                } catch { appTrimErrors[strip] = error.localizedDescription }
            } else {
                appTrimErrors[strip] = L10n.text("VAIO／AUXにAudiomeeter専用デバイスを割り当ててください。")
            }
            appTrimSupported[strip] = supported
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if strip == .virtualVAIO { if vaioAppVolumes != items { vaioAppVolumes = items } }
            else { if auxAppVolumes != items { auxAppVolumes = items } }
        }
    }

    public func setAppTrim(strip: StripID, pid: Int32, gain: Float) {
        guard let uid = strips[strip]?.deviceUID, let device = inputDevices.first(where: { $0.uid == uid }) else { return }
        let value = VMAppClient(pid: pid, gain: max(0, min(2, gain)))
        let status = AppTrimTransport.set(device.id, pid: pid, gain: value.gain)
        guard status == noErr else { audioError = L10n.text("アプリのトリム変更に失敗しました (OSStatus {0})。", [String(describing: status)]); return }
        if let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
            savedAppTrims["\(strip.rawValue):\(bundle)"] = value.gain
            saveSettings()
        }
        pollAppVolumes()
    }
}
