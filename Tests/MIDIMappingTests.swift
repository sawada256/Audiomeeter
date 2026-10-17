import Foundation
@main struct MIDIMappingTests {
    static func word(_ status: UInt32, _ data1: UInt32, _ data2: UInt32, group: UInt32 = 0) -> UInt32 {
        2 << 28 | group << 24 | status << 16 | data1 << 8 | data2
    }
    static func main() throws {
        // UMP MIDI 1.0 channel voice decoding.
        let cc = MIDIEvent.decode(umpWord: word(0xB3, 7, 100))!
        precondition(cc.trigger == MIDITrigger(kind: .controlChange, channel: 3, number: 7) && cc.raw == 100 && abs(cc.normalized - 100.0 / 127) < 1e-6)
        let on = MIDIEvent.decode(umpWord: word(0x90, 60, 90))!, off = MIDIEvent.decode(umpWord: word(0x80, 60, 64))!
        precondition(on.trigger == off.trigger && on.raw == 90 && off.raw == 0, "Note off must share the note-on trigger with value 0")
        precondition(MIDIEvent.decode(umpWord: word(0x90, 60, 0))!.raw == 0, "Velocity 0 is a release")
        precondition(MIDIEvent.decode(umpWord: word(0xE0, 0x7F, 0x7F))!.normalized == 1)
        precondition(abs(MIDIEvent.decode(umpWord: word(0xE1, 0, 0x40))!.normalized - 8192.0 / 16383) < 1e-6)
        precondition(MIDIEvent.decode(umpWord: word(0xC0, 1, 0)) == nil && MIDIEvent.decode(umpWord: 0x4090_3C00) == nil)
        precondition(MIDIEvent.umpWordCount(0x4090_3C00) == 2 && MIDIEvent.umpWordCount(0x2090_3C00) == 1 && MIDIEvent.umpWordCount(0xF000_0000) == 4)
        precondition(MIDITrigger(kind: .note, channel: 0, number: 60).displayName == "CH1 NOTE C4")

        // Encoders and absolute scaling.
        precondition(MIDIValueMode.relativeSigned.steps(1) == 1 && MIDIValueMode.relativeSigned.steps(127) == -1 && MIDIValueMode.relativeSigned.steps(65) == -63)
        precondition(MIDIValueMode.relativeOffset.steps(65) == 1 && MIDIValueMode.relativeOffset.steps(63) == -1 && MIDIValueMode.absolute.steps(10) == 0)
        precondition(MIDIMappingMath.absolute(1, .gain) == 12 && MIDIMappingMath.absolute(0, .gain) == -60 && MIDIMappingMath.absolute(0.5, .pan) == 0)
        precondition(MIDIMappingMath.clamp(20, .eqLow) == 12 && MIDIMappingMath.clamp(-3, .comp) == 0)
        precondition(MIDIControlParameter.pan.step > 0.06, "Relative PAN must escape the centre snap")

        // Soft takeover.
        var pickup = MIDIPickupState()
        let range = MIDIControlParameter.gain.range
        precondition(!pickup.accept(incoming: -60, current: 0, range: range))
        precondition(!pickup.accept(incoming: -30, current: 0, range: range))
        precondition(pickup.accept(incoming: 5, current: 0, range: range), "Crossing the current value captures it")
        precondition(pickup.accept(incoming: 6, current: 5, range: range), "A captured control follows")
        precondition(!pickup.accept(incoming: 7, current: -10, range: range), "An external change releases the capture")
        precondition(pickup.accept(incoming: -10.2, current: -10, range: range), "Reaching the value recaptures it")

        // Buttons.
        precondition(MIDIMappingMath.buttonState(pressed: true, wasPressed: false, current: false, mode: .toggle) == true)
        precondition(MIDIMappingMath.buttonState(pressed: true, wasPressed: true, current: true, mode: .toggle) == nil, "Held buttons must not retoggle")
        precondition(MIDIMappingMath.buttonState(pressed: false, wasPressed: true, current: true, mode: .toggle) == nil)
        precondition(MIDIMappingMath.buttonState(pressed: false, wasPressed: true, current: true, mode: .follow) == false)
        precondition(MIDIMappingMath.buttonState(pressed: true, wasPressed: false, current: true, mode: .follow) == nil)

        // Parameter availability and persistence.
        precondition(!MIDIControlParameter.available(for: 0).contains(.solo) && MIDIControlParameter.available(for: 103).contains(.eqLow))
        precondition(MIDIControlParameter.available(for: 100).contains(.comp) && !MIDIControlParameter.available(for: 100).contains(.pan))
        precondition(MIDIControlParameter.available(for: midiRecorderTarget) == [.record, .play, .stop])
        precondition(MIDIControlParameter.available(for: midiPluginTarget) == [.pluginParameter] && MIDIControlParameter.available(for: midiMacroTarget) == [.macroButton])
        precondition(MIDIControlParameter.available(for: midiSceneTarget) == [.recallScene] && MIDIControlParameter.recallScene.isButton && !MIDIControlParameter.pluginParameter.isButton)
        precondition(MIDIControlParameter.available(for: 105).contains(.routeA5) && MIDIControlParameter.available(for: 105).contains(.comp), "IN 4/5 are hardware strips")
        precondition(MIDIControlParameter.available(for: 104).contains(.pan) && MIDIControlParameter.routeA4.routedBus == .A4)
        precondition(MIDIMappingMath.absolute(0.5, .pluginParameter) == 0.5)
        var mapping = MIDIMapping(trigger: cc.trigger, target: 103, parameter: .eqMid, mode: .relativeOffset, button: .follow, pickup: false)
        mapping.target = 1; mapping.normalize()
        precondition(mapping.parameter == .gain, "Changing target must select a valid parameter")
        let decoded = try JSONDecoder().decode(MIDIMapping.self, from: JSONEncoder().encode(mapping))
        precondition(decoded == mapping)
        for parameter in MIDIControlParameter.allCases { precondition(!parameter.name.isEmpty) }
        print("MIDI mapping passed: UMP decode, 14-bit pitch bend, encoders, pickup, buttons, targets, persistence")
    }
}
