import Foundation

/// MIDI controller mapping: learn, persistence and application to mixer controls.
/// Every change goes through the same setters as the mouse, so the audio engine,
/// mini mixer and saved settings stay consistent.
@MainActor
extension AppState {
    func startMIDI() {
        midiInput.onEvents = { [weak self] events in MainActor.assumeIsolated { self?.handleMIDI(events) } }
        midiInput.onSourcesChanged = { [weak self] names in MainActor.assumeIsolated { self?.midiMonitor.sources = names } }
        midiInput.start()
        if midiInput.lastError != noErr {
            midiMonitor.lastMessage = L10n.text("MIDIを初期化できませんでした (OSStatus {0})", [String(describing: midiInput.lastError)])
        }
    }

    func setMIDIEnabled(_ enabled: Bool) { midiEnabled = enabled; saveSettings() }

    func addMIDIMapping(target: Int = 100, parameter: MIDIControlParameter = .gain) -> UUID {
        var mapping = MIDIMapping(target: target, parameter: parameter); mapping.normalize()
        midiMappings.append(mapping); saveSettings()
        return mapping.id
    }

    func updateMIDIMapping(_ id: UUID, _ change: (inout MIDIMapping) -> Void) {
        guard let index = midiMappings.firstIndex(where: { $0.id == id }) else { return }
        change(&midiMappings[index]); midiMappings[index].normalize()
        midiPickup[id] = nil; midiButtonsDown[id] = nil
        saveSettings()
    }

    func removeMIDIMapping(_ id: UUID) {
        midiMappings.removeAll { $0.id == id }
        if midiLearnMappingID == id { midiLearnMappingID = nil }
        midiPickup[id] = nil; midiButtonsDown[id] = nil
        saveSettings()
    }

    /// Learn for an existing control (fader right-click) or a settings row.
    func beginMIDILearn(target: Int, parameter: MIDIControlParameter) {
        let id = midiMappings.first(where: { $0.target == target && $0.parameter == parameter })?.id ?? addMIDIMapping(target: target, parameter: parameter)
        midiLearnMappingID = id
    }
    func beginMIDILearn(mapping id: UUID) { midiLearnMappingID = midiLearnMappingID == id ? nil : id }
    func cancelMIDILearn() { midiLearnMappingID = nil }

    func midiTargetName(_ target: Int) -> String {
        target == midiRecorderTarget ? L10n.text("レコーダー") : (InsertTarget.from(target)?.name ?? "?")
    }

    func handleMIDI(_ events: [MIDIEvent]) {
        guard let last = events.last else { return }
        midiMonitor.lastMessage = last.displayName
        for event in events {
            if let learning = midiLearnMappingID {
                // Ignore releases so a button's note-off does not become the learned trigger.
                guard event.raw > 0 || event.trigger.kind == .controlChange || event.trigger.kind == .pitchBend else { continue }
                updateMIDIMapping(learning) {
                    $0.trigger = event.trigger
                    if event.trigger.kind == .note { $0.mode = .absolute }
                }
                midiLearnMappingID = nil
                continue
            }
            guard midiEnabled, !isStartingAudio else { continue }
            for mapping in midiMappings where mapping.trigger == event.trigger { apply(mapping, event) }
        }
    }

    private func apply(_ mapping: MIDIMapping, _ event: MIDIEvent) {
        let parameter = mapping.parameter
        if parameter.isButton {
            let pressed = event.raw >= 64 || (event.trigger.kind == .note && event.raw > 0)
            let wasPressed = midiButtonsDown[mapping.id] ?? false
            midiButtonsDown[mapping.id] = pressed
            guard let current = buttonValue(mapping),
                  let next = MIDIMappingMath.buttonState(pressed: pressed, wasPressed: wasPressed, current: current, mode: mapping.button) else { return }
            setButton(mapping, next)
            return
        }
        guard let current = continuousValue(mapping) else { return }
        let next: Float
        if mapping.mode == .absolute {
            let incoming = MIDIMappingMath.absolute(event.normalized, parameter)
            if mapping.pickup {
                var pickup = midiPickup[mapping.id] ?? MIDIPickupState()
                let accepted = pickup.accept(incoming: incoming, current: current, range: parameter.range)
                midiPickup[mapping.id] = pickup
                guard accepted else { return }
            }
            next = incoming
        } else {
            let steps = mapping.mode.steps(event.raw)
            guard steps != 0 else { return }
            next = MIDIMappingMath.clamp(current + Float(steps) * parameter.step, parameter)
        }
        guard next != current else { return }
        setContinuous(mapping, next)
    }

    private func strip(_ mapping: MIDIMapping) -> StripID? {
        if case .strip(let strip) = InsertTarget.from(mapping.target) { return strip }
        return nil
    }
    private func bus(_ mapping: MIDIMapping) -> BusID? {
        if mapping.target >= 0, case .bus(let bus) = InsertTarget.from(mapping.target) { return bus }
        return nil
    }
    /// The PAD state the hardware strip currently shows (same selection as InputPadView).
    private func padState(_ strip: StripID) -> IntellipanState {
        guard let settings = strips[strip] else { return IntellipanState() }
        switch settings.padMode ?? .intellipan {
        case .intellipan: return settings.intellipan
        case .pan: return IntellipanState(x: settings.pan ?? 0)
        case .modulation: return settings.padModulation ?? IntellipanState()
        case .pitch: return settings.padPitch ?? IntellipanState()
        case .formant: return settings.padFormant ?? IntellipanState()
        }
    }

    private func continuousValue(_ mapping: MIDIMapping) -> Float? {
        if let bus = bus(mapping) { return mapping.parameter == .gain ? buses[bus]?.gainDB : nil }
        guard let strip = strip(mapping), let settings = strips[strip] else { return nil }
        switch mapping.parameter {
        case .gain: return settings.gainDB
        case .pan: return settings.pan ?? 0
        case .padX: return padState(strip).x
        case .padY: return padState(strip).y
        case .comp: return settings.dynamics.compKnob
        case .gate: return settings.dynamics.gateKnob
        case .eqLow: return settings.eq.lowGainDB
        case .eqMid: return settings.eq.midGainDB
        case .eqHigh: return settings.eq.highGainDB
        default: return nil
        }
    }

    private func setContinuous(_ mapping: MIDIMapping, _ value: Float) {
        if let bus = bus(mapping) { if mapping.parameter == .gain { setBusGain(bus: bus, gainDB: value) }; return }
        guard let strip = strip(mapping) else { return }
        switch mapping.parameter {
        case .gain: setStripGain(strip: strip, gainDB: value)
        case .pan: setStripPan(strip: strip, pan: value)
        case .padX: var state = padState(strip); state.x = value; setInputPad(strip: strip, state: state)
        case .padY: var state = padState(strip); state.y = value; setInputPad(strip: strip, state: state)
        case .comp: setStripDynamics(strip: strip, comp: value)
        case .gate: setStripDynamics(strip: strip, gate: value)
        case .eqLow: setStripEQ(strip: strip, low: value)
        case .eqMid: setStripEQ(strip: strip, mid: value)
        case .eqHigh: setStripEQ(strip: strip, high: value)
        default: break
        }
    }

    private func buttonValue(_ mapping: MIDIMapping) -> Bool? {
        if mapping.target == midiRecorderTarget {
            switch mapping.parameter {
            case .record: return recorderPlayer.isRecording
            case .play: return recorderPlayer.isPlaying
            case .stop: return false
            default: return nil
            }
        }
        if let bus = bus(mapping), let settings = buses[bus] {
            switch mapping.parameter {
            case .mute: return settings.isMuted
            case .busEQ: return settings.isEQEnabled
            case .limiter: return settings.isLimiterEnabled ?? true
            default: return nil
            }
        }
        guard let strip = strip(mapping), let settings = strips[strip] else { return nil }
        if let routed = mapping.parameter.routedBus { return settings.routing[routed] }
        switch mapping.parameter {
        case .mute: return settings.isMuted
        case .solo: return settings.isSolo
        default: return nil
        }
    }

    private func setButton(_ mapping: MIDIMapping, _ on: Bool) {
        if mapping.target == midiRecorderTarget {
            switch mapping.parameter {
            case .record:
                if on, !recorderPlayer.isRecording { _ = recorderPlayer.startRecording(sampleRate: engineSampleRate) }
                else if !on, recorderPlayer.isRecording { Task { @MainActor in await recorderPlayer.finishRecording() } }
            case .play: if on { recorderPlayer.play() } else { recorderPlayer.pause() }
            case .stop:
                guard on else { return }
                if recorderPlayer.isRecording { Task { @MainActor in await recorderPlayer.finishRecording() } }
                recorderPlayer.stopPlayback()
            default: break
            }
            return
        }
        if let bus = bus(mapping) {
            switch mapping.parameter {
            case .mute: toggleBusMute(bus: bus)
            case .busEQ: toggleBusEQ(bus: bus)
            case .limiter: setBusLimiter(bus: bus, enabled: on)
            default: break
            }
            return
        }
        guard let strip = strip(mapping) else { return }
        if let routed = mapping.parameter.routedBus { toggleRouting(strip: strip, bus: routed); return }
        switch mapping.parameter {
        case .mute: toggleStripMute(strip: strip)
        case .solo: toggleStripSolo(strip: strip)
        default: break
        }
    }
}
