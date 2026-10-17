import Foundation

// MARK: - Scenes

/// Which parts of the mixer a scene recalls. Devices and channel maps are never recalled.
struct SceneScope: Codable, Equatable {
    var routing = true
    var levels = true   // Faders and PAN
    var mutes = true    // Mute / Solo
    var eq = true       // Strip 3-band EQ, bus EQ
    var dynamics = true // COMP/GATE, PAD, KARAOKE, bus mode and limiter
    var inserts = true  // Insert bypass states and chain ON/OFF
}

/// A named snapshot of the mixer ("batch" save of routing and settings).
struct MixerScene: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var scope = SceneScope()
    var strips: [Int: StripSettings] = [:]
    var buses: [Int: BusSettings] = [:]
    /// Insert id -> bypass kind (nil = active), for inserts that still exist on recall.
    var insertBypass: [UUID: InsertBypassMode?] = [:]
    var chainEnabled: [Int: Bool] = [:]
    var created = Date()

    /// Merges the scoped fields of a saved strip into the current one.
    static func merge(_ saved: StripSettings, into current: StripSettings, scope: SceneScope) -> StripSettings {
        var next = current
        if scope.routing { next.routing = saved.routing }
        if scope.levels { next.gainDB = saved.gainDB; next.pan = saved.pan; next.intellipan.x = saved.intellipan.x }
        if scope.mutes { next.isMuted = saved.isMuted; next.isSolo = saved.isSolo }
        if scope.eq { next.eq = saved.eq }
        if scope.dynamics {
            next.dynamics = saved.dynamics; next.isKaraoke = saved.isKaraoke; next.padMode = saved.padMode
            next.intellipan.y = saved.intellipan.y; next.padModulation = saved.padModulation
            next.padPitch = saved.padPitch; next.padFormant = saved.padFormant; next.pitchSmooth = saved.pitchSmooth
        }
        return next
    }
    static func merge(_ saved: BusSettings, into current: BusSettings, scope: SceneScope) -> BusSettings {
        var next = current
        if scope.levels { next.gainDB = saved.gainDB }
        if scope.mutes { next.isMuted = saved.isMuted }
        if scope.eq { next.isEQEnabled = saved.isEQEnabled; next.eqConfig = saved.eqConfig }
        if scope.dynamics {
            next.mode = saved.mode; next.isLimiterEnabled = saved.isLimiterEnabled; next.limiterThresholdDB = saved.limiterThresholdDB
            next.limiterCeilingDB = saved.limiterCeilingDB; next.limiterLookaheadMS = saved.limiterLookaheadMS
        }
        return next
    }
}

// MARK: - Macro buttons

enum MacroButtonMode: String, Codable, CaseIterable {
    case push, toggle, momentary
    var name: String {
        switch self {
        case .push: return L10n.text("押す（1回実行）")
        case .toggle: return L10n.text("トグル（ON／OFF）")
        case .momentary: return L10n.text("押している間ON")
        }
    }
}

enum MacroColor: String, Codable, CaseIterable { case blue, green, orange, red, purple, gray }

/// Voicemeeter-style macro button: scripts run on press (ON) and on release/OFF.
struct MacroButton: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "Macro"
    var color = MacroColor.blue
    var mode = MacroButtonMode.push
    var onScript = ""
    var offScript = ""
    /// Toggle buttons in the same group behave as radio buttons.
    var group: Int? = nil
    var isOn = false
    var shortcut: MixerShortcut? = nil
}

/// Export/import file for macro buttons and scenes.
struct MacroLibrary: Codable {
    var version = 1
    var buttons: [MacroButton]
    var scenes: [MixerScene]
}

// MARK: - Macro script

enum MacroObject: Equatable { case strip(Int), bus(Int), scene, recorder, button(Int) }
enum MacroProperty: String, CaseIterable {
    case a1, a2, a3, a4, a5, b1, b2
    case mute, solo, gain, pan, comp, gate, eqgain1, eqgain2, eqgain3, karaoke, padx, pady
    case eqon = "eq.on", mono, limiter
    case record, play, stop, state
    var bus: BusID? {
        switch self { case .a1: return .A1; case .a2: return .A2; case .a3: return .A3; case .a4: return .A4; case .a5: return .A5; case .b1: return .B1; case .b2: return .B2; default: return nil }
    }
}
enum MacroOperation: Equatable { case set, add, subtract }
enum MacroValue: Equatable { case number(Float), toggle, text(String) }
struct MacroCommand: Equatable {
    var object: MacroObject
    var property: MacroProperty?
    var operation: MacroOperation
    var value: MacroValue
}
struct MacroScriptError: Error, Equatable { var line: Int; var message: String }

/// Parses a small Voicemeeter-like language, for example:
///   Strip[0].A1 = 1; Strip[3].Mute = toggle; Bus[1].Gain -= 3
///   Scene = "Streaming"; Recorder.Record = 1; Button[2].State = 0
/// Indices follow the visible layout: hardware strips first, then VAIO and AUX;
/// buses A1...An, then B1 and B2. Separate statements with ';' or new lines.
/// '#' and '//' start comments.
enum MacroScript {
    static func parse(_ source: String) -> (commands: [MacroCommand], errors: [MacroScriptError]) {
        var commands: [MacroCommand] = [], errors: [MacroScriptError] = []
        for (lineIndex, rawLine) in source.components(separatedBy: .newlines).enumerated() {
            var line = rawLine
            if let comment = line.range(of: "//") { line = String(line[..<comment.lowerBound]) }
            if let comment = line.firstIndex(of: "#") { line = String(line[..<comment]) }
            for statement in splitStatements(line) {
                let text = statement.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                switch parseStatement(text) {
                case .success(let command): commands.append(command)
                case .failure(let message): errors.append(MacroScriptError(line: lineIndex + 1, message: message))
                }
            }
        }
        return (commands, errors)
    }

    private enum Outcome { case success(MacroCommand), failure(String) }

    /// Splits on ';' outside double quotes.
    private static func splitStatements(_ line: String) -> [String] {
        var parts: [String] = [], current = "", quoted = false
        for character in line {
            if character == "\"" { quoted.toggle() }
            if character == ";" && !quoted { parts.append(current); current = "" } else { current.append(character) }
        }
        parts.append(current)
        return parts
    }

    private static func parseStatement(_ text: String) -> Outcome {
        let operators: [(String, MacroOperation)] = [("+=", .add), ("-=", .subtract), ("=", .set)]
        guard let (symbol, operation) = operators.first(where: { text.contains($0.0) }),
              let range = text.range(of: symbol) else { return .failure(L10n.text("「=」がありません")) }
        let left = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
        let right = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let value: MacroValue
        if right.lowercased() == "toggle" { value = .toggle }
        else if right.hasPrefix("\""), right.hasSuffix("\""), right.count >= 2 { value = .text(String(right.dropFirst().dropLast())) }
        else if let number = Float(right), number.isFinite { value = .number(number) }
        else { return .failure(L10n.text("値を読み取れません: {0}", [right])) }

        if left == "scene" {
            guard operation == .set else { return .failure(L10n.text("Sceneには「=」を使ってください")) }
            return .success(MacroCommand(object: .scene, property: nil, operation: .set, value: value))
        }
        let normalized = left.replacingOccurrences(of: "(", with: "[").replacingOccurrences(of: ")", with: "]")
        if normalized.hasPrefix("recorder.") {
            let name = String(normalized.dropFirst("recorder.".count))
            guard let property = MacroProperty(rawValue: name), [.record, .play, .stop].contains(property) else { return .failure(L10n.text("不明な項目: {0}", [left])) }
            return .success(MacroCommand(object: .recorder, property: property, operation: operation, value: value))
        }
        for (prefix, make) in [("strip[", { MacroObject.strip($0) }), ("bus[", { MacroObject.bus($0) }), ("button[", { MacroObject.button($0) })] as [(String, (Int) -> MacroObject)] {
            guard normalized.hasPrefix(prefix), let close = normalized.firstIndex(of: "]") else { continue }
            let indexText = normalized[normalized.index(normalized.startIndex, offsetBy: prefix.count)..<close]
            guard let index = Int(indexText.trimmingCharacters(in: .whitespaces)), index >= 0 else { return .failure(L10n.text("番号を読み取れません: {0}", [left])) }
            let rest = normalized[normalized.index(after: close)...]
            guard rest.hasPrefix(".") else { return .failure(L10n.text("項目がありません: {0}", [left])) }
            let name = String(rest.dropFirst())
            guard let property = MacroProperty(rawValue: name) else { return .failure(L10n.text("不明な項目: {0}", [left])) }
            let object = make(index)
            let allowed: [MacroProperty]
            switch object {
            case .strip: allowed = [.a1, .a2, .a3, .a4, .a5, .b1, .b2, .mute, .solo, .gain, .pan, .comp, .gate, .eqgain1, .eqgain2, .eqgain3, .karaoke, .padx, .pady]
            case .bus: allowed = [.mute, .gain, .eqon, .mono, .limiter]
            default: allowed = [.state]
            }
            guard allowed.contains(property) else { return .failure(L10n.text("この対象では使えない項目: {0}", [left])) }
            if operation != .set && !isContinuous(property) { return .failure(L10n.text("「+=」「-=」は数値の項目にだけ使えます")) }
            return .success(MacroCommand(object: object, property: property, operation: operation, value: value))
        }
        return .failure(L10n.text("不明な対象: {0}", [left]))
    }

    static func isContinuous(_ property: MacroProperty) -> Bool {
        [.gain, .pan, .comp, .gate, .eqgain1, .eqgain2, .eqgain3, .padx, .pady].contains(property)
    }
    /// Result of applying an operation to a numeric property.
    static func number(current: Float, operation: MacroOperation, value: MacroValue, range: ClosedRange<Float>) -> Float? {
        guard case .number(let amount) = value else { return nil }
        let next: Float
        switch operation { case .set: next = amount; case .add: next = current + amount; case .subtract: next = current - amount }
        return min(range.upperBound, max(range.lowerBound, next))
    }
    /// Result for a switch property; `toggle` inverts, numbers are ON when nonzero.
    static func flag(current: Bool, value: MacroValue) -> Bool? {
        switch value { case .toggle: return !current; case .number(let number): return number != 0; case .text: return nil }
    }
}
