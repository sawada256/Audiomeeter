import Foundation
@main struct DesktopControlsTests {
    static func main() throws {
        precondition(MixerMediaKey.action(0x0a00) == .increase)
        precondition(MixerMediaKey.action((1 << 16) | 0x0a00) == .decrease)
        precondition(MixerMediaKey.action((7 << 16) | 0x0a00) == .mute)
        precondition(MixerMediaKey.action((7 << 16) | 0x0a01) == nil)
        precondition(MixerMediaKey.action(0x0b00) == nil)
        precondition(MixerMediaKey.isVolumeKey(0x0b00))
        precondition(!MixerMediaKey.isVolumeKey((16 << 16) | 0x0a00))
        for eventType: UInt32 in [1, 2, 3, 4, 5, 6, 7, 22, 25, 26, 27] {
            precondition(!MixerMediaKey.shouldConsume(eventType: eventType, subtype: 8, data: 0x0a00))
        }
        precondition(!MixerMediaKey.shouldConsume(eventType: 14, subtype: 7, data: 0x0a00))
        precondition(MixerMediaKey.shouldConsume(eventType: 14, subtype: 8, data: 0x0a00))
        precondition(MixerMediaKey.shouldConsume(eventType: 14, subtype: 8, data: 0x0b00))
        var prefs = DesktopControlsPreferences()
        prefs.gainStep = .nan; prefs.overlayOpacity = 0; prefs.mediaTarget = 999
        prefs.hotkeys = [MixerHotkeyBinding(target: 104, action: .decrease, shortcut: MixerShortcut(keyCode: 80, modifiers: 4096)), MixerHotkeyBinding(target: 999)]
        prefs.normalize()
        precondition(prefs.gainStep == 1 && prefs.overlayOpacity == 0.15 && prefs.mediaTarget == 0 && prefs.hotkeys.count == 1)
        prefs.gainStep = 0.5; prefs.overlayMode = .held; prefs.overlayCorner = .bottomLeft
        prefs.showAppTrims = true; prefs.appTrimSource = .automatic
        prefs.overlayChannels[104] = MiniMixerChannel(fader: true, meter: false)
        prefs.reverseTrackpadScroll = false; prefs.reverseMouseScroll = true
        let restored = try JSONDecoder().decode(DesktopControlsPreferences.self, from: JSONEncoder().encode(prefs))
        precondition(restored == prefs)
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(prefs)) as! [String: Any]
        oldJSON.removeValue(forKey: "reverseTrackpadScroll"); oldJSON.removeValue(forKey: "reverseMouseScroll")
        var migrated = try JSONDecoder().decode(DesktopControlsPreferences.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        migrated.normalize()
        precondition(migrated.reverseTrackpadScroll == true && migrated.reverseMouseScroll == true)
        precondition(migrated.hotkeys == prefs.hotkeys && migrated.overlayChannels == prefs.overlayChannels)
        precondition(MixerShortcut.overlayDefault.displayName == "⌃⇧Space")
        print("Media key down/up/repeat isolation, preference bounds, channel selection and shortcut persistence passed")
    }
}
