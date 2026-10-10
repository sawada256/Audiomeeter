import Foundation

struct MixerShortcut: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier flags: command, shift, option, control.
    static let overlayDefault = MixerShortcut(keyCode: 49, modifiers: 4096 | 512)
    var displayName: String {
        let names: [UInt32: String] = [49:"Space", 36:"Return", 48:"Tab", 53:"Esc", 123:"←",124:"→",125:"↓",126:"↑", 122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20",0:"A",11:"B",8:"C",2:"D",14:"E",3:"F",5:"G",4:"H",34:"I",38:"J",40:"K",37:"L",46:"M",45:"N",31:"O",35:"P",12:"Q",15:"R",1:"S",17:"T",32:"U",9:"V",13:"W",7:"X",16:"Y",6:"Z",18:"1",19:"2",20:"3",21:"4",23:"5",22:"6",26:"7",28:"8",25:"9",29:"0",27:"−",24:"＋"]
        return (modifiers & 4096 != 0 ? "⌃" : "") + (modifiers & 2048 != 0 ? "⌥" : "") + (modifiers & 512 != 0 ? "⇧" : "") + (modifiers & 256 != 0 ? "⌘" : "") + (names[keyCode] ?? "Key \(keyCode)")
    }
}
enum MixerHotkeyAction: String, Codable, CaseIterable {
    case increase, decrease, mute
    var name: String { switch self { case .increase: return L10n.text("上げる"); case .decrease: return L10n.text("下げる"); case .mute: return L10n.text("ミュート切替") } }
}
enum MixerMediaKey {
    static func shouldConsume(eventType: UInt32, subtype: Int16, data: Int) -> Bool {
        eventType == 14 && subtype == 8 && isVolumeKey(data)
    }
    static func isVolumeKey(_ data: Int) -> Bool { let key = (data >> 16) & 0xffff; return key == 0 || key == 1 || key == 7 }
    static func action(_ data: Int) -> MixerHotkeyAction? {
        guard isVolumeKey(data), (data >> 8) & 0xff == 0x0a else { return nil }
        let key = (data >> 16) & 0xffff
        if key == 7 && data & 1 != 0 { return nil } // Mute must not toggle on autorepeat.
        return key == 0 ? .increase : key == 1 ? .decrease : .mute
    }
}
struct MixerHotkeyBinding: Codable, Equatable, Identifiable {
    var id = UUID()
    var target = 0
    var action = MixerHotkeyAction.increase
    var shortcut: MixerShortcut?
}
enum MiniMixerMode: String, Codable, CaseIterable {
    case off, always, held
    var name: String { switch self { case .off: return L10n.text("非表示"); case .always: return L10n.text("常時表示"); case .held: return L10n.text("キーを押している間") } }
}
enum MiniMixerCorner: String, Codable, CaseIterable {
    case topRight, topLeft, bottomRight, bottomLeft
    var name: String { switch self { case .topRight: return L10n.text("右上"); case .topLeft: return L10n.text("左上"); case .bottomRight: return L10n.text("右下"); case .bottomLeft: return L10n.text("左下") } }
}
enum MiniMixerAppSource: String, Codable, CaseIterable {
    case automatic, vaio, aux, both
    var name: String { switch self { case .automatic: return L10n.text("OSの出力先に追従"); case .vaio: return "VAIO"; case .aux: return "AUX"; case .both: return L10n.text("VAIO と AUX") } }
}
struct MiniMixerChannel: Codable, Equatable {
    var fader = false
    var meter = false
}
struct DesktopControlsPreferences: Codable, Equatable {
    var gainStep: Double = 1
    // Optional fields preserve compatibility with settings saved before scroll controls.
    var reverseTrackpadScroll: Bool? = true
    var reverseMouseScroll: Bool? = true
    var mediaKeysEnabled = false
    var mediaTarget = 0
    var keepVirtualVolumeAtMaximum = true
    var hotkeys: [MixerHotkeyBinding] = []
    var overlayMode = MiniMixerMode.held
    var overlayCorner = MiniMixerCorner.topRight
    var overlayOpacity: Double = 0.9
    var overlayShortcut = MixerShortcut.overlayDefault
    var overlayChannels: [Int: MiniMixerChannel] = [0: MiniMixerChannel(fader: true, meter: true), 3: MiniMixerChannel(fader: true, meter: true)]
    var showAppTrims = false
    var appTrimSource = MiniMixerAppSource.automatic
    mutating func normalize() {
        reverseTrackpadScroll = reverseTrackpadScroll ?? true
        reverseMouseScroll = reverseMouseScroll ?? true
        gainStep = gainStep.isFinite ? min(12, max(0.1, gainStep)) : 1
        overlayOpacity = overlayOpacity.isFinite ? min(1, max(0.15, overlayOpacity)) : 0.9
        if !([0,1,2,3,4,100,101,102,103,104].contains(mediaTarget)) { mediaTarget = 0 }
        hotkeys = Array(hotkeys.filter { [0,1,2,3,4,100,101,102,103,104].contains($0.target) }.prefix(30))
    }
}
