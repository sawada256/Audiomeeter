import Foundation
@main struct MacroScriptTests {
    static func main() throws {
        // Voicemeeter-style statements, separators, comments and both index brackets.
        let script = """
        Strip[0].A1 = 1; Strip(3).Mute = toggle   // comment
        Bus[1].Gain -= 3.5
        # full-line comment
        Scene = "配信; 夜"
        Recorder.Record = 1; Button[2].State = 0
        bus[0].eq.on = 1
        """
        let parsed = MacroScript.parse(script)
        precondition(parsed.errors.isEmpty, "\(parsed.errors)")
        precondition(parsed.commands == [
            MacroCommand(object: .strip(0), property: .a1, operation: .set, value: .number(1)),
            MacroCommand(object: .strip(3), property: .mute, operation: .set, value: .toggle),
            MacroCommand(object: .bus(1), property: .gain, operation: .subtract, value: .number(3.5)),
            MacroCommand(object: .scene, property: nil, operation: .set, value: .text("配信; 夜")),
            MacroCommand(object: .recorder, property: .record, operation: .set, value: .number(1)),
            MacroCommand(object: .button(2), property: .state, operation: .set, value: .number(0)),
            MacroCommand(object: .bus(0), property: .eqon, operation: .set, value: .number(1)),
        ], "\(parsed.commands)")

        // Errors carry line numbers; invalid combinations are rejected.
        let bad = MacroScript.parse("Strip[0].A1 = 1\nBus[0].Solo = 1\nStrip[x].Mute = 1\nStrip[0].Mute += 1\nFoo = 2\nStrip[0].Gain = loud")
        precondition(bad.commands.count == 1 && bad.errors.map(\.line) == [2, 3, 4, 5, 6], "\(bad.errors)")

        // Value helpers.
        precondition(MacroScript.number(current: 0, operation: .subtract, value: .number(70), range: -60...12) == -60)
        precondition(MacroScript.number(current: -6, operation: .add, value: .number(3), range: -60...12) == -3)
        precondition(MacroScript.number(current: 0, operation: .set, value: .toggle, range: -60...12) == nil)
        precondition(MacroScript.flag(current: true, value: .toggle) == false && MacroScript.flag(current: false, value: .number(2)) == true)

        // Scenes recall only their scope and never devices or channels.
        var saved = StripSettings(deviceUID: "saved-device", gainDB: -12, isMuted: true, routing: RoutingMatrix(a1: false, b2: true))
        saved.pan = 0.5; saved.leftChannel = 4; saved.eq.lowGainDB = 6
        var current = StripSettings(deviceUID: "live-device", gainDB: 0, routing: RoutingMatrix(a1: true))
        current.leftChannel = 0
        var scope = SceneScope(); scope.eq = false
        let merged = MixerScene.merge(saved, into: current, scope: scope)
        precondition(merged.deviceUID == "live-device" && merged.leftChannel == 0, "Devices and channels are never recalled")
        precondition(merged.gainDB == -12 && merged.pan == 0.5 && merged.isMuted && merged.routing == RoutingMatrix(b2: true))
        precondition(merged.eq.lowGainDB == 0, "Out-of-scope EQ must be kept")
        var bus = BusSettings(gainDB: -3, isMuted: true); bus.limiterThresholdDB = -6; bus.deviceUID = "a"
        var live = BusSettings(); live.deviceUID = "b"
        scope = SceneScope(); scope.mutes = false
        let mergedBus = MixerScene.merge(bus, into: live, scope: scope)
        precondition(mergedBus.gainDB == -3 && !mergedBus.isMuted && mergedBus.limiterThresholdDB == -6 && mergedBus.deviceUID == "b")

        // Library round trip, including legacy routing without A4/A5 keys.
        var scene = MixerScene(name: "Live"); scene.strips[0] = saved; scene.insertBypass[UUID()] = .latency; scene.insertBypass[UUID()] = .some(nil)
        var button = MacroButton(); button.mode = .toggle; button.group = 2; button.onScript = "Scene = \"Live\""
        let library = MacroLibrary(buttons: [button], scenes: [scene])
        let decoded = try JSONDecoder().decode(MacroLibrary.self, from: JSONEncoder().encode(library))
        precondition(decoded.buttons == [button] && decoded.scenes == [scene])
        let legacy = try JSONDecoder().decode(RoutingMatrix.self, from: Data(#"{"a1":true,"a2":false,"a3":false,"b1":true,"b2":false}"#.utf8))
        precondition(legacy == RoutingMatrix(a1: true, b1: true) && legacy[.A5] == false)
        print("Macro scripts passed: parsing, errors, value helpers, scoped scene merge, library and legacy routing decode")
    }
}
