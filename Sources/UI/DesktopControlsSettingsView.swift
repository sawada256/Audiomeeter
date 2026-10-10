import SwiftUI
import AppKit

struct DesktopControlsSettingsView: View {
    @ObservedObject var state: AppState
    private let channels = StripID.allCases.map { InsertTarget.strip($0) } + BusID.allCases.map { InsertTarget.bus($0) }
    private func binding<T>(_ key: WritableKeyPath<DesktopControlsPreferences, T>) -> Binding<T> {
        Binding(get: { state.desktopControls[keyPath: key] }, set: { value in
            var preferences = state.desktopControls; preferences[keyPath: key] = value; state.setDesktopControls(preferences)
        })
    }
    private func channelBinding(_ id: Int, _ key: WritableKeyPath<MiniMixerChannel, Bool>) -> Binding<Bool> {
        Binding(get: { (state.desktopControls.overlayChannels[id] ?? MiniMixerChannel())[keyPath: key] }, set: { value in
            var preferences = state.desktopControls, channel = preferences.overlayChannels[id] ?? MiniMixerChannel()
            channel[keyPath: key] = value; preferences.overlayChannels[id] = channel; state.setDesktopControls(preferences)
        })
    }
    private func hotkeyBinding<T>(_ id: UUID, _ key: WritableKeyPath<MixerHotkeyBinding, T>, fallback: T) -> Binding<T> {
        Binding(get: { state.desktopControls.hotkeys.first { $0.id == id }?[keyPath: key] ?? fallback }, set: { value in
            var p = state.desktopControls
            if let index = p.hotkeys.firstIndex(where: { $0.id == id }) { p.hotkeys[index][keyPath: key] = value; state.setDesktopControls(p) }
        })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("ホットキー").font(.headline)
                Stepper(value: binding(\.gainStep), in: 0.1...12, step: 0.1) {
                    Text(String(format: "1回のゲイン変動: %.1f dB", state.desktopControls.gainStep))
                }
                Toggle("トラックパッドのフェーダースクロール方向を反転", isOn: Binding(get: { state.desktopControls.reverseTrackpadScroll ?? true }, set: { binding(\.reverseTrackpadScroll).wrappedValue = $0 }))
                Toggle("マウスホイールのフェーダースクロール方向を反転", isOn: Binding(get: { state.desktopControls.reverseMouseScroll ?? true }, set: { binding(\.reverseMouseScroll).wrappedValue = $0 }))
                Text("メイン画面と常駐ミニミキサーに適用します。滑らかなスクロールを送るマウスはトラックパッド側の設定が適用される場合があります。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Macの音量キーをフェーダー操作に置き換える", isOn: binding(\.mediaKeysEnabled))
                Picker("音量キーの対象", selection: binding(\.mediaTarget)) {
                    ForEach(channels) { Text($0.name).tag($0.id) }
                }
                Text("F10のミュート／F11・F12の音量操作を選択した対象に割り当てます。fnで通常のFキーとして送られる場合は、下の個別キー設定を使ってください。")
                    .font(.caption).foregroundStyle(.secondary)
                if state.desktopControls.mediaKeysEnabled {
                    Button("ホットキーを再接続") { DesktopControlsCoordinator.current?.hotkeys.resume() }
                    Button("アクセシビリティ設定を開く") { MixerHotkeys.openAccessibilitySettings() }
                    Text("音量キーの置換には、このアプリのアクセシビリティ許可が必要です。許可後は自動で有効になります。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("VAIO／AUXのOS音量を常に100%・ミュート解除に維持", isOn: binding(\.keepVirtualVolumeAtMaximum))
                Text("仮想デバイス側の音量を0にせず、音量調整はフェーダー／アプリ別トリムで行います。物理出力デバイスのOS音量は変更しません。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(state.desktopControls.hotkeys) { row in
                    HStack(spacing: 6) {
                        Picker("対象", selection: hotkeyBinding(row.id, \.target, fallback: 0)) { ForEach(channels) { Text($0.name).tag($0.id) } }.labelsHidden().frame(width: 85)
                        Picker("操作", selection: hotkeyBinding(row.id, \.action, fallback: .increase)) { ForEach(MixerHotkeyAction.allCases, id: \.self) { Text($0.name).tag($0) } }.labelsHidden().frame(width: 110)
                        ShortcutRecorder(shortcut: hotkeyBinding(row.id, \.shortcut, fallback: nil)).frame(height: 25)
                        Button { var p = state.desktopControls; p.hotkeys.removeAll { $0.id == row.id }; state.setDesktopControls(p) } label: { Image(systemName: "trash") }
                    }
                }
                Button("＋ 個別のホットキーを追加") { var p = state.desktopControls; p.hotkeys.append(MixerHotkeyBinding()); state.setDesktopControls(p) }
                    .disabled(state.desktopControls.hotkeys.count >= 30)
                Text(state.desktopControlsStatus).font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("常駐ミニミキサー").font(.headline)
                Picker("表示方法", selection: binding(\.overlayMode)) { ForEach(MiniMixerMode.allCases, id: \.self) { Text($0.name).tag($0) } }
                Picker("表示位置", selection: binding(\.overlayCorner)) { ForEach(MiniMixerCorner.allCases, id: \.self) { Text($0.name).tag($0) } }
                HStack {
                    Text("不透明度")
                    Slider(value: binding(\.overlayOpacity), in: 0.15...1)
                    Text("\(Int(state.desktopControls.overlayOpacity * 100))%").monospacedDigit().frame(width: 45)
                }
                HStack {
                    Text("押している間の表示キー")
                    ShortcutRecorder(shortcut: Binding(get: { state.desktopControls.overlayShortcut }, set: { if let value = $0 { var p = state.desktopControls; p.overlayShortcut = value; state.setDesktopControls(p) } }), clearAllowed: false).frame(height: 25)
                }
                Text("初期キーは⌃⇧Spaceです。⌃Space／⌃⌥Spaceは入力ソース切替と競合する場合があります。キー欄をクリックして割り当て、Escでキャンセル。通常キーには⌃／⌥／⇧／⌘のいずれかを付けてください。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack { Text("表示するチャンネル").frame(maxWidth: .infinity, alignment: .leading); Text("フェーダー").frame(width: 88); Text("メーター").frame(width: 88) }
                ForEach(channels) { channel in
                    HStack {
                        Text(channel.name).frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("\(channel.name) フェーダー", isOn: channelBinding(channel.id, \.fader)).labelsHidden().frame(width: 88)
                        Toggle("\(channel.name) メーター", isOn: channelBinding(channel.id, \.meter)).labelsHidden().frame(width: 88)
                    }
                }
                Divider()
                Toggle("アプリ別トリムを表示", isOn: binding(\.showAppTrims))
                Picker("アプリ別トリムの対象", selection: binding(\.appTrimSource)) { ForEach(MiniMixerAppSource.allCases, id: \.self) { Text($0.name).tag($0) } }
                Text("OSの出力先に追従: VoicemeeterならVAIO、Voicemeeter AUXならAUX。専用ドライバーから現在出力中のアプリ一覧を取得します。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12)
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: MixerShortcut?
    var clearAllowed = true
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.current = shortcut; view.changed = { shortcut = $0 }; view.clearAllowed = clearAllowed
        if !view.recording { view.title = shortcut?.displayName ?? "キーを設定…" }
        view.toolTip = clearAllowed ? "クリックしてキーを設定。右クリックで解除" : "クリックして表示キーを設定"
    }
    final class RecorderButton: NSButton {
        var current: MixerShortcut?, changed: ((MixerShortcut?) -> Void)?
        var clearAllowed = true, recording = false
        init() { super.init(frame: .zero); bezelStyle = .rounded; font = .systemFont(ofSize: 11); target = self; action = #selector(record) }
        required init?(coder: NSCoder) { fatalError() }
        override var acceptsFirstResponder: Bool { true }
        @objc private func record() {
            recording = true; title = "キーを押してください…"
            DesktopControlsCoordinator.current?.hotkeys.suspend()
            window?.makeFirstResponder(self)
        }
        private func finish() { recording = false; title = current?.displayName ?? "キーを設定…"; DesktopControlsCoordinator.current?.hotkeys.resume() }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == 53 { finish(); return }
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { modifiers |= 256 }
            if event.modifierFlags.contains(.shift) { modifiers |= 512 }
            if event.modifierFlags.contains(.option) { modifiers |= 2048 }
            if event.modifierFlags.contains(.control) { modifiers |= 4096 }
            let functionKeys: Set<UInt16> = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
            guard modifiers != 0 || functionKeys.contains(event.keyCode) else { title = "修飾キーと一緒に押してください"; return }
            current = MixerShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers); changed?(current); finish()
        }
        override func resignFirstResponder() -> Bool { if recording { finish() }; return super.resignFirstResponder() }
        override func rightMouseDown(with event: NSEvent) { guard clearAllowed else { return }; current = nil; changed?(nil); finish() }
    }
}
