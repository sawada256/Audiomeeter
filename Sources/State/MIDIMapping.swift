import Foundation

/// Controller messages that can be learned. Pitch bend covers Mackie-style 14-bit faders.
enum MIDIMessageKind: String, Codable, CaseIterable { case controlChange, note, pitchBend }

struct MIDITrigger: Codable, Hashable {
    var kind: MIDIMessageKind
    var channel: UInt8 // 0...15
    var number: UInt8 = 0 // CC or note number; 0 for pitch bend
    var displayName: String {
        switch kind {
        case .controlChange: return "CH\(channel + 1) CC\(number)"
        case .note: return "CH\(channel + 1) NOTE \(Self.noteName(number))"
        case .pitchBend: return "CH\(channel + 1) PITCH BEND"
        }
    }
    static func noteName(_ number: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[Int(number) % 12])\(Int(number) / 12 - 1)"
    }
}

struct MIDIEvent: Equatable {
    var trigger: MIDITrigger
    var raw: UInt8 // 7-bit value: CC value, note velocity (0 = note off), pitch-bend MSB
    var normalized: Float // 0...1, with 14-bit resolution for pitch bend
    var displayName: String { trigger.displayName + " = \(raw)" }

    /// Decodes one MIDI 1.0 channel-voice Universal MIDI Packet word (message type 2).
    static func decode(umpWord word: UInt32) -> MIDIEvent? {
        guard word >> 28 == 2 else { return nil }
        let status = UInt8((word >> 16) & 0xF0), channel = UInt8((word >> 16) & 0x0F)
        let data1 = UInt8((word >> 8) & 0x7F), data2 = UInt8(word & 0x7F)
        switch status {
        case 0xB0: return MIDIEvent(trigger: MIDITrigger(kind: .controlChange, channel: channel, number: data1), raw: data2, normalized: Float(data2) / 127)
        case 0x90: return MIDIEvent(trigger: MIDITrigger(kind: .note, channel: channel, number: data1), raw: data2, normalized: Float(data2) / 127)
        case 0x80: return MIDIEvent(trigger: MIDITrigger(kind: .note, channel: channel, number: data1), raw: 0, normalized: 0)
        case 0xE0:
            let value = Int(data1) | Int(data2) << 7
            return MIDIEvent(trigger: MIDITrigger(kind: .pitchBend, channel: channel), raw: data2, normalized: Float(value) / 16383)
        default: return nil
        }
    }
    /// Number of 32-bit words in a Universal MIDI Packet, from its message type nibble.
    static func umpWordCount(_ firstWord: UInt32) -> Int {
        [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4][Int(firstWord >> 28)]
    }
}

/// Pseudo targets; mixer targets reuse InsertTarget ids (buses 0...6, strips 100...106).
let midiRecorderTarget = -1
let midiPluginTarget = -2
let midiMacroTarget = -3
let midiSceneTarget = -4

enum MIDIControlParameter: String, Codable, CaseIterable {
    case gain, mute, solo, pan, padX, padY, comp, gate, eqLow, eqMid, eqHigh
    case routeA1, routeA2, routeA3, routeA4, routeA5, routeB1, routeB2
    case busEQ, limiter
    case record, play, stop
    case pluginParameter, macroButton, recallScene

    var isButton: Bool {
        switch self {
        case .mute, .solo, .routeA1, .routeA2, .routeA3, .routeA4, .routeA5, .routeB1, .routeB2, .busEQ, .limiter, .record, .play, .stop, .macroButton, .recallScene: return true
        default: return false
        }
    }
    var range: ClosedRange<Float> {
        switch self {
        case .gain: return -60...12
        case .pan, .padX, .padY: return -1...1
        case .comp, .gate: return 0...10
        case .eqLow, .eqMid, .eqHigh: return -12...12
        default: return 0...1
        }
    }
    /// One relative-encoder detent.
    var step: Float {
        switch self {
        case .gain: return 0.5
        case .pan, .padX, .padY: return 0.0625 // Larger than the PAN centre snap.
        case .comp, .gate: return 0.1
        case .eqLow, .eqMid, .eqHigh: return 0.25
        case .pluginParameter: return 1.0 / 128
        default: return 1
        }
    }
    var name: String {
        switch self {
        case .gain: return L10n.text("フェーダー")
        case .mute: return "Mute"
        case .solo: return "Solo"
        case .pan: return "PAN"
        case .padX: return L10n.text("PAD 横軸")
        case .padY: return L10n.text("PAD 縦軸")
        case .comp: return "COMP"
        case .gate: return "GATE"
        case .eqLow: return "BASS"
        case .eqMid: return "MED"
        case .eqHigh: return "TREBLE"
        case .routeA1: return "→ A1"
        case .routeA2: return "→ A2"
        case .routeA3: return "→ A3"
        case .routeA4: return "→ A4"
        case .routeA5: return "→ A5"
        case .routeB1: return "→ B1"
        case .routeB2: return "→ B2"
        case .busEQ: return "EQ ON/OFF"
        case .limiter: return "LIMIT ON/OFF"
        case .record: return L10n.text("録音 開始／停止")
        case .play: return L10n.text("再生／一時停止")
        case .stop: return L10n.text("停止")
        case .pluginParameter: return L10n.text("パラメーター")
        case .macroButton: return L10n.text("マクロボタン")
        case .recallScene: return L10n.text("シーン呼出")
        }
    }
    var routedBus: BusID? {
        switch self { case .routeA1: return .A1; case .routeA2: return .A2; case .routeA3: return .A3; case .routeA4: return .A4; case .routeA5: return .A5; case .routeB1: return .B1; case .routeB2: return .B2; default: return nil }
    }
    /// Parameters that exist on a target (InsertTarget id, or midiRecorderTarget).
    static func available(for target: Int) -> [Self] {
        switch target {
        case midiRecorderTarget: return [.record, .play, .stop]
        case midiPluginTarget: return [.pluginParameter]
        case midiMacroTarget: return [.macroButton]
        case midiSceneTarget: return [.recallScene]
        default: break
        }
        if target < 100 { return [.gain, .mute, .busEQ, .limiter] }
        let routes: [Self] = [.routeA1, .routeA2, .routeA3, .routeA4, .routeA5, .routeB1, .routeB2]
        if let strip = StripID(rawValue: target - 100), strip.isVirtual { return [.gain, .mute, .solo, .pan, .eqLow, .eqMid, .eqHigh] + routes }
        return [.gain, .mute, .solo, .padX, .padY, .comp, .gate] + routes
    }
}

enum MIDIValueMode: String, Codable, CaseIterable {
    case absolute, relativeSigned, relativeOffset
    var name: String {
        switch self {
        case .absolute: return L10n.text("絶対値")
        case .relativeSigned: return L10n.text("相対（1/127）")
        case .relativeOffset: return L10n.text("相対（64中心）")
        }
    }
    /// Encoder detents encoded in a 7-bit value: two's complement or binary offset.
    func steps(_ raw: UInt8) -> Int {
        switch self {
        case .absolute: return 0
        case .relativeSigned: return raw < 64 ? Int(raw) : Int(raw) - 128
        case .relativeOffset: return Int(raw) - 64
        }
    }
}

enum MIDIButtonMode: String, Codable, CaseIterable {
    case toggle, follow
    var name: String { self == .toggle ? L10n.text("押すたびに切替") : L10n.text("値に追従（127=ON）") }
}

struct MIDIMapping: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: MIDITrigger?
    var target = 100
    var parameter = MIDIControlParameter.gain
    var mode = MIDIValueMode.absolute
    var button = MIDIButtonMode.toggle
    var pickup = true
    /// For midiPluginTarget: the insert (InsertConfig.id) and its parameter index.
    var pluginInsertID: UUID? = nil
    var pluginParameter: Int? = nil
    /// For midiMacroTarget / midiSceneTarget.
    var macroID: UUID? = nil
    var sceneID: UUID? = nil

    /// Keep the parameter valid when the target changes.
    mutating func normalize() {
        let options = MIDIControlParameter.available(for: target)
        if !options.contains(parameter) { parameter = options[0] }
    }
}

/// Soft takeover: an absolute control only grabs a value once it reaches or crosses it,
/// so moving a physical knob never makes the parameter jump.
struct MIDIPickupState {
    var captured = false
    var lastIncoming: Float?
    var lastWritten: Float?

    mutating func accept(incoming: Float, current: Float, range: ClosedRange<Float>) -> Bool {
        let tolerance = (range.upperBound - range.lowerBound) / 127 * 1.5
        // Another control (mouse, hotkey) moved the value: require a new pickup.
        if captured, let lastWritten, abs(lastWritten - current) > tolerance { captured = false }
        if !captured {
            if abs(incoming - current) <= tolerance { captured = true }
            else if let previous = lastIncoming, (previous - current) * (incoming - current) <= 0 { captured = true }
        }
        lastIncoming = incoming
        if captured { lastWritten = incoming }
        return captured
    }
}

enum MIDIMappingMath {
    static func absolute(_ normalized: Float, _ parameter: MIDIControlParameter) -> Float {
        let range = parameter.range
        let value = range.lowerBound + (range.upperBound - range.lowerBound) * min(1, max(0, normalized))
        return parameter == .gain ? (value * 10).rounded() / 10 : value
    }
    static func clamp(_ value: Float, _ parameter: MIDIControlParameter) -> Float {
        min(parameter.range.upperBound, max(parameter.range.lowerBound, value))
    }
    /// Button transitions: `toggle` reacts to presses only; `follow` mirrors the value.
    static func buttonState(pressed: Bool, wasPressed: Bool, current: Bool, mode: MIDIButtonMode) -> Bool? {
        switch mode {
        case .toggle: return pressed && !wasPressed ? !current : nil
        case .follow: return pressed != current ? pressed : nil
        }
    }
}
