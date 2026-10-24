import Foundation
import AppKit
import UniformTypeIdentifiers

/// Macro buttons and scenes. Everything is applied through the same setters as
/// the mixer UI, so the engine, saved settings and the mini mixer stay in sync.
@MainActor
extension AppState {
    // MARK: Scenes

    @discardableResult
    func saveScene(name: String, scope: SceneScope = SceneScope(), replacing id: UUID? = nil) -> UUID {
        var scene = MixerScene(name: name.isEmpty ? L10n.text("シーン {0}", [String(scenes.count + 1)]) : name, scope: scope)
        for (strip, settings) in strips { scene.strips[strip.rawValue] = settings }
        for (bus, settings) in buses { scene.buses[bus.rawValue] = settings }
        for configs in insertConfigs.values { for config in configs { scene.insertBypass[config.id] = config.effectiveBypass } }
        scene.chainEnabled = insertChainEnabled
        if let id, let index = scenes.firstIndex(where: { $0.id == id }) {
            scene.id = id; scene.name = name.isEmpty ? scenes[index].name : name; scene.scope = scenes[index].scope
            scenes[index] = scene
        } else { scenes.append(scene) }
        saveSettings()
        return scene.id
    }

    func updateScene(_ id: UUID, _ change: (inout MixerScene) -> Void) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        change(&scenes[index]); saveSettings()
    }
    func deleteScene(_ id: UUID) { scenes.removeAll { $0.id == id }; midiMappings.removeAll { $0.sceneID == id }; saveSettings() }

    func recallScene(named name: String) {
        if let scene = scenes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { recallScene(scene.id) }
        else { audioError = L10n.text("シーン「{0}」が見つかりません。", [name]) }
    }

    /// Applies one scene in a single update per strip/bus (devices and channels untouched).
    func recallScene(_ id: UUID) {
        guard !isStartingAudio, let scene = scenes.first(where: { $0.id == id }) else { return }
        var candidate = strips
        for (raw, saved) in scene.strips {
            guard let strip = StripID(rawValue: raw), let current = candidate[strip] else { continue }
            candidate[strip] = MixerScene.merge(saved, into: current, scope: scene.scope)
        }
        if scene.scope.routing && InternalBusRouting.hasCycle(candidate) {
            audioError = L10n.text("内部バスへ戻す経路が循環するため、このルーティングは有効にできません。")
            for (strip, settings) in strips { candidate[strip]?.routing = settings.routing }
        }
        for (strip, settings) in candidate where settings != strips[strip] {
            strips[strip] = settings
            // The engine's device assignment (nil for hidden strips) is never replaced by a recall.
            engine.updateStripSettings(strip: strip) { let device = $0.deviceUID; $0 = settings; $0.deviceUID = device }
        }
        for (raw, saved) in scene.buses {
            guard let bus = BusID(rawValue: raw), let current = buses[bus] else { continue }
            let next = MixerScene.merge(saved, into: current, scope: scene.scope)
            if next != current { buses[bus] = next; engine.updateBusSettings(bus: bus) { let device = $0.deviceUID; $0 = next; $0.deviceUID = device } }
        }
        if scene.scope.inserts {
            for (target, configs) in insertConfigs {
                for config in configs {
                    if let saved = scene.insertBypass[config.id], saved != config.effectiveBypass {
                        setInsertBypass(target: target, id: config.id, mode: saved)
                    }
                }
                if let enabled = scene.chainEnabled[target.id], enabled != insertChainIsEnabled(target) { toggleInsertChain(target) }
            }
        }
        activeSceneID = id
        saveSettings()
    }

    // MARK: Macro buttons

    /// Re-registers global hotkeys only when macro shortcuts actually changed
    /// (not on every keystroke while a script is edited).
    private func macroShortcutsChanged(from previous: [MixerShortcut?]) {
        if previous != macroButtons.map(\.shortcut) { DesktopControlsCoordinator.current?.hotkeys.configure() }
    }
    func addMacroButton() {
        guard macroButtons.count < 64 else { return }
        var button = MacroButton(); button.name = L10n.text("ボタン {0}", [String(macroButtons.count + 1)])
        macroButtons.append(button); saveSettings()
    }
    func updateMacroButton(_ id: UUID, _ change: (inout MacroButton) -> Void) {
        guard let index = macroButtons.firstIndex(where: { $0.id == id }) else { return }
        let previous = macroButtons.map(\.shortcut)
        change(&macroButtons[index]); saveSettings(); macroShortcutsChanged(from: previous)
    }
    func deleteMacroButton(_ id: UUID) {
        let previous = macroButtons.map(\.shortcut)
        macroButtons.removeAll { $0.id == id }; midiMappings.removeAll { $0.macroID == id }
        saveSettings(); macroShortcutsChanged(from: previous)
    }
    func moveMacroButton(_ id: UUID, by offset: Int) {
        guard let index = macroButtons.firstIndex(where: { $0.id == id }), macroButtons.indices.contains(index + offset) else { return }
        let previous = macroButtons.map(\.shortcut)
        macroButtons.swapAt(index, index + offset); saveSettings(); macroShortcutsChanged(from: previous)
    }

    /// Click, hotkey or MIDI press (`down`) and release.
    func macroButton(_ id: UUID, down: Bool, depth: Int = 0) {
        guard depth < 4, let index = macroButtons.firstIndex(where: { $0.id == id }) else { return }
        let button = macroButtons[index]
        switch button.mode {
        case .push: if down { runMacro(button.onScript, depth: depth) }
        case .momentary: setMacroState(id, on: down, depth: depth)
        case .toggle: if down { setMacroState(id, on: !button.isOn, depth: depth) }
        }
    }
    func setMacroState(_ id: UUID, on: Bool, depth: Int = 0) {
        guard depth < 4, let index = macroButtons.firstIndex(where: { $0.id == id }) else { return }
        let button = macroButtons[index]
        if button.mode == .push { if on { runMacro(button.onScript, depth: depth) }; return }
        guard button.isOn != on else { return }
        if on, let group = button.group {
            for other in macroButtons where other.id != id && other.group == group && other.isOn { setMacroState(other.id, on: false, depth: depth + 1) }
        }
        macroButtons[index].isOn = on
        runMacro(on ? button.onScript : button.offScript, depth: depth)
        saveSettings()
    }

    /// Runs a script; returns parse errors (also shown to the user).
    @discardableResult
    func runMacro(_ script: String, depth: Int = 0) -> [MacroScriptError] {
        let parsed = MacroScript.parse(script)
        for command in parsed.commands { execute(command, depth: depth) }
        if let first = parsed.errors.first { audioError = L10n.text("マクロの{0}行目: {1}", [String(first.line), first.message]) }
        return parsed.errors
    }

    private func execute(_ command: MacroCommand, depth: Int) {
        switch command.object {
        case .scene:
            switch command.value {
            case .text(let name): recallScene(named: name)
            case .number(let number) where scenes.indices.contains(Int(number)): recallScene(scenes[Int(number)].id)
            default: break
            }
        case .recorder:
            let on: Bool
            switch command.property {
            case .record: on = MacroScript.flag(current: recorderPlayer.isRecording, value: command.value) ?? false
                if on && !recorderPlayer.isRecording { _ = recorderPlayer.startRecording(sampleRate: engineSampleRate) }
                if !on && recorderPlayer.isRecording { Task { @MainActor in await recorderPlayer.finishRecording() } }
            case .play: on = MacroScript.flag(current: recorderPlayer.isPlaying, value: command.value) ?? false
                if on { recorderPlayer.play() } else { recorderPlayer.pause() }
            case .stop:
                if recorderPlayer.isRecording { Task { @MainActor in await recorderPlayer.finishRecording() } }
                recorderPlayer.stopPlayback()
            default: break
            }
        case .button(let index):
            guard macroButtons.indices.contains(index) else { return }
            let button = macroButtons[index]
            if let on = MacroScript.flag(current: button.isOn, value: command.value) { setMacroState(button.id, on: on, depth: depth + 1) }
        case .strip(let index):
            guard visibleStrips.indices.contains(index), let property = command.property else { return }
            executeStrip(visibleStrips[index], property, command)
        case .bus(let index):
            guard visibleBuses.indices.contains(index), let property = command.property else { return }
            executeBus(visibleBuses[index], property, command)
        }
    }

    private func executeStrip(_ strip: StripID, _ property: MacroProperty, _ command: MacroCommand) {
        guard let settings = strips[strip] else { return }
        func number(_ current: Float, _ range: ClosedRange<Float>) -> Float? { MacroScript.number(current: current, operation: command.operation, value: command.value, range: range) }
        if let bus = property.bus {
            if visibleBuses.contains(bus), let on = MacroScript.flag(current: settings.routing[bus], value: command.value), on != settings.routing[bus] { toggleRouting(strip: strip, bus: bus) }
            return
        }
        switch property {
        case .mute: if let on = MacroScript.flag(current: settings.isMuted, value: command.value), on != settings.isMuted { toggleStripMute(strip: strip) }
        case .solo: if let on = MacroScript.flag(current: settings.isSolo, value: command.value), on != settings.isSolo { toggleStripSolo(strip: strip) }
        case .karaoke: if strip.isVirtual, let on = MacroScript.flag(current: settings.isKaraoke, value: command.value), on != settings.isKaraoke { toggleStripKaraoke(strip: strip) }
        case .gain: if let value = number(settings.gainDB, -60...12) { setStripGain(strip: strip, gainDB: value) }
        case .pan: if let value = number(settings.pan ?? 0, -1...1) { setStripPan(strip: strip, pan: value) }
        case .comp: if let value = number(settings.dynamics.compKnob, 0...10) { setStripDynamics(strip: strip, comp: value) }
        case .gate: if let value = number(settings.dynamics.gateKnob, 0...10) { setStripDynamics(strip: strip, gate: value) }
        case .eqgain1: if let value = number(settings.eq.lowGainDB, -12...12) { setStripEQ(strip: strip, low: value) }
        case .eqgain2: if let value = number(settings.eq.midGainDB, -12...12) { setStripEQ(strip: strip, mid: value) }
        case .eqgain3: if let value = number(settings.eq.highGainDB, -12...12) { setStripEQ(strip: strip, high: value) }
        case .padx, .pady:
            var state: PadState
            switch settings.padMode ?? .colorPan {
            case .colorPan: state = settings.colorPad
            case .pan: state = PadState(x: settings.pan ?? 0)
            case .modulation: state = settings.padModulation ?? PadState()
            case .pitch: state = settings.padPitch ?? PadState()
            case .formant: state = settings.padFormant ?? PadState()
            }
            if property == .padx, let value = number(state.x, -1...1) { state.x = value } else if property == .pady, let value = number(state.y, -1...1) { state.y = value }
            setInputPad(strip: strip, state: state)
        default: break
        }
    }

    private func executeBus(_ bus: BusID, _ property: MacroProperty, _ command: MacroCommand) {
        guard let settings = buses[bus] else { return }
        switch property {
        case .mute: if let on = MacroScript.flag(current: settings.isMuted, value: command.value), on != settings.isMuted { toggleBusMute(bus: bus) }
        case .gain: if let value = MacroScript.number(current: settings.gainDB, operation: command.operation, value: command.value, range: -60...12) { setBusGain(bus: bus, gainDB: value) }
        case .eqon: if let on = MacroScript.flag(current: settings.isEQEnabled, value: command.value), on != settings.isEQEnabled { toggleBusEQ(bus: bus) }
        case .mono: if let on = MacroScript.flag(current: settings.mode == .mono, value: command.value) { setBusMode(bus: bus, mode: on ? .mono : .normal) }
        case .limiter: if let on = MacroScript.flag(current: settings.isLimiterEnabled ?? true, value: command.value) { setBusLimiter(bus: bus, enabled: on) }
        default: break
        }
    }

    // MARK: Diagnostics

    func diagnostics(resetPeak: Bool) -> EngineDiagnostics {
        var report = engine.diagnostics(resetPeak: resetPeak)
        report.recordingDroppedFrames = recorderPlayer.recordingDroppedFrames
        report.playbackUnderruns = recorderPlayer.playbackUnderruns
        report.plugins = InsertTarget.all.flatMap { target in
            (engine.inserts[target] ?? []).map {
                EngineDiagnostics.Plugin(id: $0.config.id, target: target.name, name: $0.config.name, latency: $0.latency, lateBlocks: $0.lateBlocks,
                                         renderMicros: $0.renderMicros, restarts: pluginRestartCounts[$0.config.id] ?? 0, status: $0.status)
            }
        }
        return report
    }

    // MARK: Export / import

    func exportMacroLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Audiomeeter-Macros.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(MacroLibrary(buttons: macroButtons, scenes: scenes)).write(to: url, options: .atomic)
        } catch { audioError = error.localizedDescription }
    }
    /// Imports buttons and scenes, replacing entries with the same id and appending new ones.
    func importMacroLibrary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let library = try JSONDecoder().decode(MacroLibrary.self, from: Data(contentsOf: url))
            for button in library.buttons.prefix(64) {
                if let index = macroButtons.firstIndex(where: { $0.id == button.id }) { macroButtons[index] = button }
                else if macroButtons.count < 64 { macroButtons.append(button) }
            }
            for scene in library.scenes.prefix(128) {
                if let index = scenes.firstIndex(where: { $0.id == scene.id }) { scenes[index] = scene }
                else if scenes.count < 128 { scenes.append(scene) }
            }
            saveSettings(); DesktopControlsCoordinator.current?.hotkeys.configure()
        } catch { audioError = L10n.text("読み込めませんでした: {0}", [error.localizedDescription]) }
    }
}
