import Foundation
import CoreAudio

public enum BusID: Int, CaseIterable, Identifiable, Codable {
    case A1 = 0
    case A2 = 1
    case A3 = 2
    // Optional physical buses A4/A5 (5+5 layout). Raw values keep B1/B2 stable in saved settings.
    case A4 = 5
    case A5 = 6
    case B1 = 3
    case B2 = 4

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .A1: return "A1"
        case .A2: return "A2"
        case .A3: return "A3"
        case .A4: return "A4"
        case .A5: return "A5"
        case .B1: return "B1"
        case .B2: return "B2"
        }
    }

    public var isPhysical: Bool {
        return !isVirtual
    }
    /// 0-based position among physical buses (A1 = 0), or nil for B buses.
    public var physicalIndex: Int? {
        switch self { case .A1: return 0; case .A2: return 1; case .A3: return 2; case .A4: return 3; case .A5: return 4; default: return nil }
    }

    public var isVirtual: Bool {
        return self == .B1 || self == .B2
    }

    public var defaultLabel: String {
        switch self {
        case .A1: return "HARDWARE OUT 1 (Master Clock)"
        case .A2: return "HARDWARE OUT 2"
        case .A3: return "HARDWARE OUT 3"
        case .A4: return "HARDWARE OUT 4"
        case .A5: return "HARDWARE OUT 5"
        case .B1: return "VIRTUAL OUT B1 (VAIO)"
        case .B2: return "VIRTUAL OUT B2 (AUX)"
        }
    }
}

public enum StripID: Int, CaseIterable, Identifiable, Codable {
    case hardware1 = 0
    case hardware2 = 1
    case hardware3 = 2
    // Optional hardware strips; raw values keep VAIO/AUX stable in saved settings.
    case hardware4 = 5
    case hardware5 = 6
    case virtualVAIO = 3
    case virtualAUX = 4

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .hardware1: return "HARDWARE INPUT 1"
        case .hardware2: return "HARDWARE INPUT 2"
        case .hardware3: return "HARDWARE INPUT 3"
        case .hardware4: return "HARDWARE INPUT 4"
        case .hardware5: return "HARDWARE INPUT 5"
        case .virtualVAIO: return "AUDIOMEETER VAIO"
        case .virtualAUX: return "AUDIOMEETER AUX"
        }
    }

    public var shortName: String {
        switch self {
        case .hardware1: return "IN 1"
        case .hardware2: return "IN 2"
        case .hardware3: return "IN 3"
        case .hardware4: return "IN 4"
        case .hardware5: return "IN 5"
        case .virtualVAIO: return "VAIO"
        case .virtualAUX: return "AUX"
        }
    }

    public var isHardware: Bool {
        return !isVirtual
    }
    /// 0-based position among hardware strips, or nil for virtual strips.
    public var hardwareIndex: Int? {
        switch self { case .hardware1: return 0; case .hardware2: return 1; case .hardware3: return 2; case .hardware4: return 3; case .hardware5: return 4; default: return nil }
    }

    public var isVirtual: Bool {
        return self == .virtualVAIO || self == .virtualAUX
    }
}

public struct AudioDeviceInfo: Identifiable, Hashable, Codable {
    public var id: AudioObjectID
    public var name: String
    public var uid: String
    public var inChannels: Int
    public var outChannels: Int
    public var sampleRate: Double
    public var isDefaultInput: Bool
    public var isDefaultOutput: Bool

    public init(
        id: AudioObjectID,
        name: String,
        uid: String,
        inChannels: Int,
        outChannels: Int,
        sampleRate: Double,
        isDefaultInput: Bool = false,
        isDefaultOutput: Bool = false
    ) {
        self.id = id
        self.name = name
        self.uid = uid
        self.inChannels = inChannels
        self.outChannels = outChannels
        self.sampleRate = sampleRate
        self.isDefaultInput = isDefaultInput
        self.isDefaultOutput = isDefaultOutput
    }
}

public struct RoutingMatrix: Codable, Equatable {
    public var a1: Bool
    public var a2: Bool
    public var a3: Bool
    public var b1: Bool
    public var b2: Bool
    // Optional so settings saved before A4/A5 existed still decode.
    public var a4: Bool?
    public var a5: Bool?

    public init(a1: Bool = false, a2: Bool = false, a3: Bool = false, b1: Bool = false, b2: Bool = false, a4: Bool = false, a5: Bool = false) {
        self.a1 = a1
        self.a2 = a2
        self.a3 = a3
        self.b1 = b1
        self.b2 = b2
        self.a4 = a4
        self.a5 = a5
    }

    public static func == (lhs: RoutingMatrix, rhs: RoutingMatrix) -> Bool {
        BusID.allCases.allSatisfy { lhs[$0] == rhs[$0] }
    }

    public subscript(bus: BusID) -> Bool {
        get {
            switch bus {
            case .A1: return a1
            case .A2: return a2
            case .A3: return a3
            case .A4: return a4 ?? false
            case .A5: return a5 ?? false
            case .B1: return b1
            case .B2: return b2
            }
        }
        set {
            switch bus {
            case .A1: a1 = newValue
            case .A2: a2 = newValue
            case .A3: a3 = newValue
            case .A4: a4 = newValue
            case .A5: a5 = newValue
            case .B1: b1 = newValue
            case .B2: b2 = newValue
            }
        }
    }
}

public struct EQ3Band: Codable, Equatable {
    public var lowGainDB: Float   // -12.0 ... +12.0
    public var midGainDB: Float   // -12.0 ... +12.0
    public var highGainDB: Float  // -12.0 ... +12.0

    public init(lowGainDB: Float = 0.0, midGainDB: Float = 0.0, highGainDB: Float = 0.0) {
        self.lowGainDB = lowGainDB
        self.midGainDB = midGainDB
        self.highGainDB = highGainDB
    }
}

public struct PadState: Codable, Equatable {
    public var x: Float // -1.0 to 1.0 (Color / Pan)
    public var y: Float // -1.0 to 1.0 (Echo / Brightness)

    public init(x: Float = 0.0, y: Float = 0.0) {
        self.x = x
        self.y = y
    }
}

public struct DynamicsConfig: Codable, Equatable {
    public var compKnob: Float // 0.0 ... 10.0
    public var gateKnob: Float // 0.0 ... 10.0

    public init(compKnob: Float = 0.0, gateKnob: Float = 0.0) {
        self.compKnob = compKnob
        self.gateKnob = gateKnob
    }
}

public enum FilterType: String, CaseIterable, Identifiable, Codable {
    case peaking = "Peaking / Bell"
    case lowShelf = "Low Shelf"
    case highShelf = "High Shelf"
    case highPass = "High Pass (Low Cut)"
    case lowPass = "Low Pass (High Cut)"
    case notch = "Notch"

    public var id: String { rawValue }
}

public struct EQBandConfig: Codable, Equatable, Identifiable {
    public var id: Int
    public var type: FilterType
    public var freqHz: Float
    public var gainDB: Float
    public var q: Float
    public var isEnabled: Bool

    public init(id: Int, type: FilterType, freqHz: Float, gainDB: Float = 0.0, q: Float = 1.0, isEnabled: Bool = true) {
        self.id = id
        self.type = type
        self.freqHz = freqHz
        self.gainDB = gainDB
        self.q = q
        self.isEnabled = isEnabled
    }
}

public struct MasterEQConfig: Codable, Equatable {
    public var isEnabled: Bool
    public var bands: [EQBandConfig]

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
        self.bands = [
            EQBandConfig(id: 0, type: .lowShelf, freqHz: 80.0, gainDB: 0.0, q: 0.707),
            EQBandConfig(id: 1, type: .peaking, freqHz: 250.0, gainDB: 0.0, q: 1.0),
            EQBandConfig(id: 2, type: .peaking, freqHz: 800.0, gainDB: 0.0, q: 1.0),
            EQBandConfig(id: 3, type: .peaking, freqHz: 2500.0, gainDB: 0.0, q: 1.0),
            EQBandConfig(id: 4, type: .peaking, freqHz: 7500.0, gainDB: 0.0, q: 1.0),
            EQBandConfig(id: 5, type: .highShelf, freqHz: 12000.0, gainDB: 0.0, q: 0.707)
        ]
    }
}

public enum RecorderFormat: String, CaseIterable, Identifiable, Codable {
    case wav16 = "WAV 16-bit"
    case wav24 = "WAV 24-bit"
    case wavFloat32 = "WAV 32-bit Float"
    case aac128 = "AAC 128 kbps"
    case aac192 = "AAC 192 kbps"
    case aac256 = "AAC 256 kbps"
    case aac320 = "AAC 320 kbps"

    public var id: String { rawValue }
    public var isWAV: Bool { self == .wav16 || self == .wav24 || self == .wavFloat32 }
    public var fileExtension: String { isWAV ? "wav" : "m4a" }
}

public struct AppVolumeItem: Identifiable, Equatable, Codable {
    public var pid: Int32
    public var name: String
    public var volume: Float // 0.0 to 1.5, default 1.0

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, volume: Float = 1.0) {
        self.pid = pid
        self.name = name
        self.volume = volume
    }
}

public enum BusMode: String, CaseIterable, Identifiable, Codable {
    case normal = "Normal"
    case mixdown = "Mix Down"
    case mono = "Mono"

    public var id: String { rawValue }
}

public enum InputPadMode: String, Codable, CaseIterable {
    case colorPan = "COLOR PAN", pan = "PAN", modulation = "MODULATION", pitch = "PITCH", formant = "FORMANT (EXP)"
    /// Settings saved by builds before the rename used "INTELLIPAN" for the color pad.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = raw == "INTELLIPAN" ? .colorPan : (Self(rawValue: raw) ?? .colorPan)
    }
}

public struct StripSettings: Codable, Equatable {
    public var deviceUID: String?
    public var channelOffset: Int? = nil
    public var leftChannel: Int? = nil
    public var rightChannel: Int? = nil
    public var gainDB: Float          // -60.0 to +12.0, default 0.0
    public var isMuted: Bool
    public var isSolo: Bool
    public var routing: RoutingMatrix
    public var colorPad: PadState
    public var dynamics: DynamicsConfig
    public var eq: EQ3Band
    public var isKaraoke: Bool        // Vocal / Center Cancel
    public var padMode: InputPadMode? = nil
    public var padModulation: PadState? = nil
    public var padPitch: PadState? = nil
    public var padFormant: PadState? = nil
    public var pitchSmooth: Bool? = nil
    public var pan: Float? = nil // Stereo balance: -1 left, 0 center, +1 right.
    // "intellipan" is the settings key used before the color pad was renamed.
    private enum CodingKeys: String, CodingKey {
        case deviceUID, channelOffset, leftChannel, rightChannel, gainDB, isMuted, isSolo, routing
        case colorPad = "intellipan"
        case dynamics, eq, isKaraoke, padMode, padModulation, padPitch, padFormant, pitchSmooth, pan
    }

    public init(
        deviceUID: String? = nil,
        gainDB: Float = 0.0,
        isMuted: Bool = false,
        isSolo: Bool = false,
        routing: RoutingMatrix = RoutingMatrix(),
        colorPad: PadState = PadState(),
        dynamics: DynamicsConfig = DynamicsConfig(),
        eq: EQ3Band = EQ3Band(),
        isKaraoke: Bool = false
    ) {
        self.deviceUID = deviceUID
        self.gainDB = gainDB
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.routing = routing
        self.colorPad = colorPad
        self.dynamics = dynamics
        self.eq = eq
        self.isKaraoke = isKaraoke
    }
}

public enum BusEQPosition: String, Codable, CaseIterable {
    case beforeInserts, afterInserts, beforeLimiter, afterLimiter
    public var title: String { switch self {
    case .beforeInserts: return "EQ → INSERT → LIMIT"
    case .afterInserts: return "INSERT → EQ → LIMIT (After INSERT)"
    case .beforeLimiter: return "INSERT → EQ → LIMIT (Before LIMIT)"
    case .afterLimiter: return "INSERT → LIMIT → EQ"
    } }
    public var order: [BusProcessingStage] { switch self {
    case .beforeInserts: return [.eq, .preInserts, .fader, .postInserts, .limiter]
    case .afterInserts, .beforeLimiter: return [.preInserts, .fader, .postInserts, .eq, .limiter]
    case .afterLimiter: return [.preInserts, .fader, .postInserts, .limiter, .eq]
    } }
    public static func migrated(_ order: [BusProcessingStage]?) -> Self {
        guard let order, BusProcessingStage.isValid(order), let eq = order.firstIndex(of: .eq) else { return .beforeLimiter }
        if eq < order.firstIndex(of: .preInserts)! { return .beforeInserts }
        if eq > order.firstIndex(of: .limiter)! { return .afterLimiter }
        return .beforeLimiter
    }
}

public enum BusProcessingStage: String, Codable, CaseIterable, Identifiable {
    case preInserts, eq, fader, limiter, postInserts
    public var id: String { rawValue }
    public var title: String { switch self {
    case .preInserts: return "PRE INSERTS"
    case .postInserts: return "POST INSERTS"
    case .eq: return "EQ"
    case .fader: return "FADER / MODE"
    case .limiter: return "LIMIT"
    } }
    public static let standard: [Self] = [.preInserts, .fader, .postInserts, .eq, .limiter]
    /// 3 bits per stage, so the render callback reads the order from one atomic word.
    static func packed(_ order: [Self]) -> UInt64 {
        order.enumerated().reduce(0) { $0 | UInt64($1.element.code) << UInt64(3 * $1.offset) }
    }
    static func unpacked(_ value: UInt64, at index: Int) -> Self {
        switch (value >> UInt64(3 * index)) & 7 { case 0: return .preInserts; case 1: return .eq; case 2: return .fader; case 3: return .limiter; default: return .postInserts }
    }
    private var code: Int { switch self { case .preInserts: return 0; case .eq: return 1; case .fader: return 2; case .limiter: return 3; case .postInserts: return 4 } }
    public static func isValid(_ order: [Self]) -> Bool {
        guard order.count == 5, Set(order).count == 5,
              let pre = order.firstIndex(of: .preInserts), let fader = order.firstIndex(of: .fader), let post = order.firstIndex(of: .postInserts) else { return false }
        return pre < fader && fader < post
    }
}

public struct BusSettings: Codable, Equatable {
    public var deviceUID: String?
    public var channelOffset: Int? = nil
    public var leftChannel: Int? = nil
    public var rightChannel: Int? = nil
    public var gainDB: Float          // -60.0 to +12.0, default 0.0
    public var isMuted: Bool
    public var mode: BusMode
    public var isEQEnabled: Bool
    public var eqConfig: MasterEQConfig
    public var delayMilliseconds: Double? = nil // Additional device calibration after plugin PDC.
    public var limiterThresholdDB: Float? = nil
    public var limiterCeilingDB: Float? = nil
    public var limiterLookaheadMS: Double? = nil
    public var isLimiterEnabled: Bool? = true // nil preserves legacy settings

    public init(
        deviceUID: String? = nil,
        gainDB: Float = 0.0,
        isMuted: Bool = false,
        mode: BusMode = .normal,
        isEQEnabled: Bool = false,
        eqConfig: MasterEQConfig = MasterEQConfig()
    ) {
        self.deviceUID = deviceUID
        self.gainDB = gainDB
        self.isMuted = isMuted
        self.mode = mode
        self.isEQEnabled = isEQEnabled
        self.eqConfig = eqConfig
    }
}

public struct MeterLevel {
    public var limiterReductionDB: Float = 0
    public var leftPeakDB: Float
    public var rightPeakDB: Float
    public var leftRMSDB: Float
    public var rightRMSDB: Float

    public init(leftPeakDB: Float = -100.0, rightPeakDB: Float = -100.0, leftRMSDB: Float = -100.0, rightRMSDB: Float = -100.0) {
        self.leftPeakDB = leftPeakDB
        self.rightPeakDB = rightPeakDB
        self.leftRMSDB = leftRMSDB
        self.rightRMSDB = rightRMSDB
    }
}

/// UIDs of Audiomeeter's dedicated HAL devices. Each list also accepts the UID of the
/// developer's earlier prototype driver (before the project was renamed Audiomeeter),
/// so existing installations keep working; new installers only create Audiomeeter UIDs.
public enum DedicatedDevice {
    public static let vaio: Set<String> = ["Audiomeeter_UID", "Voicemeeter_UID"]
    public static let aux: Set<String> = ["AudiomeeterAUX_UID", "VoicemeeterAUX_UID"]
    public static let b1: Set<String> = ["AudiomeeterB1_UID", "VoicemeeterB1_UID"]
    public static let b2: Set<String> = ["AudiomeeterB2_UID", "VoicemeeterB2_UID"]
    public static var returns: Set<String> { b1.union(b2) }
    /// Display names of the same devices, used only to auto-assign on first launch.
    static let vaioNames: Set<String> = ["Audiomeeter", "Audiomeeter VAIO", "Voicemeeter", "Voicemeeter VAIO"]
    static let auxNames: Set<String> = ["Audiomeeter AUX", "Voicemeeter AUX"]
    public static func returnBus(_ uid: String?) -> BusID? {
        guard let uid else { return nil }
        return b1.contains(uid) ? .B1 : b2.contains(uid) ? .B2 : nil
    }
}

/// Reject audible feedback cycles between internal return buses.
public enum InternalBusRouting {
    public static func source(_ uid: String?) -> BusID? {
        DedicatedDevice.returnBus(uid)
    }
    public static func hasCycle(_ strips: [StripID: StripSettings]) -> Bool {
        func reaches(_ current: BusID, _ target: BusID, _ visited: Set<BusID>) -> Bool {
            guard !visited.contains(current) else { return false }
            let nextVisited = visited.union([current])
            for setting in strips.values where source(setting.deviceUID) == current {
                for next in [BusID.B1, .B2] where setting.routing[next] {
                    if next == target || reaches(next, target, nextVisited) { return true }
                }
            }
            return false
        }
        return reaches(.B1, .B1, []) || reaches(.B2, .B2, [])
    }
}

public enum StereoPanControl {
    public static func normalized(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        let clamped = min(1, max(-1, value))
        return abs(clamped) <= 0.06 ? 0 : clamped
    }
    public static func label(_ value: Float) -> String {
        let percentage = Int((abs(value) * 100).rounded())
        return percentage == 0 ? "C" : "\(value < 0 ? "L" : "R")\(percentage)"
    }
}

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

/// Latency-preserving ("soft") bypass keeps the worker and PDC running; full bypass
/// removes the plugin from the signal path and its latency from compensation.
public enum InsertBypassMode: String, Codable, CaseIterable {
    case latency, full
    var other: Self { self == .latency ? .full : .latency }
}
