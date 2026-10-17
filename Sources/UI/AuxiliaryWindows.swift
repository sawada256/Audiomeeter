import SwiftUI
import AppKit

/// Non-modal tool windows that stay open beside the mixer.
@MainActor
enum AuxiliaryWindows {
    enum Kind: String { case macros, routing, diagnostics }
    private static var windows: [Kind: NSWindow] = [:]

    static func show(_ kind: Kind) {
        if let window = windows[kind] { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let state = AppState.shared
        let (title, size, view): (String, NSSize, AnyView) = {
            switch kind {
            case .macros: return (L10n.text("マクロボタンとシーン"), NSSize(width: 1020, height: 640), AnyView(MacroButtonsView(state: state)))
            case .routing: return (L10n.text("ルーティングマトリクス"), NSSize(width: 640, height: 420), AnyView(RoutingMatrixView(state: state)))
            case .diagnostics: return (L10n.text("診断"), NSSize(width: 760, height: 560), AnyView(DiagnosticsView(state: state)))
            }
        }()
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.preferredColorScheme(.dark))
        window.center()
        windows[kind] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    /// Language changes rebuild windows on next open.
    static func closeAll() { for window in windows.values { window.close() }; windows.removeAll() }
}

enum InsertBypassUI {
    static func help(_ slot: InsertConfig) -> String {
        let state: String
        switch slot.effectiveBypass {
        case nil: state = L10n.text("有効")
        case .latency: state = L10n.text("簡易バイパス（遅延維持）")
        case .full: state = L10n.text("完全バイパス（経路から除外）")
        }
        return "\(slot.position.rawValue) · \(slot.name) · \(state)\n" + L10n.text("クリック: 既定のバイパス、⌥クリック: もう一方のバイパス、右クリック: 編集")
    }
}

// MARK: - Routing matrix

struct RoutingMatrixView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var localization = LocalizationStore.shared
    var body: some View {
        let buses = state.visibleBuses
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .center, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Text(L10n.text("入力 ＼ 出力")).font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                    ForEach(buses) { bus in
                        VStack(spacing: 1) {
                            Text(bus.name).font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text(state.outputDevices.first { $0.uid == state.buses[bus]?.deviceUID }?.name ?? "—").font(.system(size: 8)).lineLimit(1).frame(width: 64)
                        }.foregroundStyle(bus.isPhysical ? VMTheme.ledAActive : VMTheme.ledBActive)
                    }
                    Text("Mute").font(.caption)
                }
                ForEach(state.visibleStrips) { strip in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(strip.shortName).font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text(state.inputDevices.first { $0.uid == state.strips[strip]?.deviceUID }?.name ?? "—").font(.system(size: 8)).lineLimit(1).frame(width: 110, alignment: .leading)
                        }
                        ForEach(buses) { bus in
                            let on = state.strips[strip]?.routing[bus] ?? false
                            LEDButton(label: on ? "●" : "", isActive: on, activeColor: bus.isPhysical ? VMTheme.ledAActive : VMTheme.ledBActive) {
                                state.toggleRouting(strip: strip, bus: bus)
                            }.frame(width: 44)
                        }
                        LEDButton(label: "M", isActive: state.strips[strip]?.isMuted ?? false, activeColor: VMTheme.ledMuteActive) { state.toggleStripMute(strip: strip) }.frame(width: 34)
                    }
                }
                GridRow {
                    Text(L10n.text("レコーダー再生")).font(.system(size: 11, weight: .bold, design: .monospaced))
                    ForEach(buses) { bus in
                        let on = state.recorderPlayer.playbackRouting[bus] ?? false
                        LEDButton(label: on ? "●" : "", isActive: on, activeColor: VMTheme.textAccent) { state.recorderPlayer.playbackRouting[bus] = !on }.frame(width: 44)
                    }
                    Text("")
                }
            }.padding(16)
        }
        .id(localization.language)
        .background(VMTheme.consoleBg)
    }
}

// MARK: - Diagnostics

struct DiagnosticsView: View {
    @ObservedObject var state: AppState
    @State private var report = EngineDiagnostics()
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private func ms(_ samples: Int) -> String { String(format: "%d smp / %.2f ms", samples, Double(samples) / max(1, report.sampleRate) * 1000) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 24) {
                    metric(L10n.text("処理負荷"), String(format: "%.0f %%", report.load * 100), warn: report.load > 0.7)
                    metric(L10n.text("1ブロック処理"), String(format: "%.0f µs (%@ %.0f)", report.cycleMicros, L10n.text("最大"), report.cycleMaxMicros), warn: report.cycleMaxMicros > report.blockMicros)
                    metric(L10n.text("締切超過"), "\(report.cycleOverruns)", warn: report.cycleOverruns > 0)
                    metric(L10n.text("ブロック"), String(format: "%d smp / %.2f ms", report.bufferFrames, report.blockMicros / 1000), warn: false)
                }
                HStack(spacing: 24) {
                    metric(L10n.text("A1出力の機器遅延"), ms(report.masterLatency), warn: false)
                    metric(L10n.text("録音の欠落"), "\(report.recordingDroppedFrames)", warn: report.recordingDroppedFrames > 0)
                    metric(L10n.text("再生の途切れ"), "\(report.playbackUnderruns)", warn: report.playbackUnderruns > 0)
                    if report.usingFallbackClock { Text(L10n.text("A1未設定: 内部タイマーで動作中")).foregroundStyle(.orange) }
                }
                Text(L10n.text("入力")).font(.headline)
                pathTable(report.inputs)
                Text(L10n.text("出力")).font(.headline)
                pathTable(report.outputs)
                Text(L10n.text("プラグイン")).font(.headline)
                if report.plugins.isEmpty { Text(L10n.text("インサートなし")).foregroundStyle(.secondary) }
                ForEach(report.plugins) { plugin in
                    HStack {
                        Text("\(plugin.target) · \(plugin.name)").frame(width: 220, alignment: .leading).lineLimit(1)
                        Text(ms(plugin.latency)).frame(width: 150, alignment: .leading)
                        Text(String(format: "%.0f µs", plugin.renderMicros)).frame(width: 70, alignment: .trailing)
                        Text(L10n.text("遅延 {0}", [String(plugin.lateBlocks)])).frame(width: 80, alignment: .trailing).foregroundStyle(plugin.lateBlocks > 0 ? .orange : .secondary)
                        Text(L10n.text("再起動 {0}", [String(plugin.restarts)])).frame(width: 80, alignment: .trailing)
                        Text(plugin.status).foregroundStyle(.orange).lineLimit(1)
                    }.font(.caption.monospaced())
                }
                Text(L10n.text("経路の遅延はプラグイン・プロセス通信・同期ディレイの合計です。機器と独立クロック間のリング（各3ブロック程度）は含みません。直結＝A1と同じ機器で、リングとクロック補正を通りません。"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("最大値をリセット")) { report = state.diagnostics(resetPeak: true) }
            }.padding(16)
        }
        .background(VMTheme.consoleBg)
        .onAppear { report = state.diagnostics(resetPeak: false) }
        .onReceive(timer) { _ in report = state.diagnostics(resetPeak: false) }
    }
    private func metric(_ title: String, _ value: String, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced)).foregroundStyle(warn ? .orange : .primary)
        }
    }
    private func modeName(_ mode: EngineDiagnostics.PathMode) -> String {
        switch mode {
        case .none: return "—"
        case .master: return L10n.text("マスター")
        case .direct: return L10n.text("直結")
        case .ring: return L10n.text("リング＋補正")
        case .internalReturn: return L10n.text("内部バス")
        }
    }
    private func pathTable(_ paths: [EngineDiagnostics.Path]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("").frame(width: 50)
                Text(L10n.text("方式")).frame(width: 110, alignment: .leading)
                Text(L10n.text("リング")).frame(width: 60, alignment: .trailing)
                Text("ppm").frame(width: 70, alignment: .trailing)
                Text(L10n.text("不足")).frame(width: 60, alignment: .trailing)
                Text(L10n.text("溢れ")).frame(width: 60, alignment: .trailing)
                Text(L10n.text("経路の遅延")).frame(width: 170, alignment: .trailing)
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(paths) { path in
                HStack {
                    Text(path.name).frame(width: 50, alignment: .leading)
                    Text(modeName(path.mode)).frame(width: 110, alignment: .leading)
                    Text(path.mode == .ring ? String(format: "%.0f %%", path.fill * 100) : "—").frame(width: 60, alignment: .trailing)
                    Text(path.mode == .ring ? String(format: "%+.0f", path.correctionPPM) : "—").frame(width: 70, alignment: .trailing)
                    Text("\(path.underruns)").frame(width: 60, alignment: .trailing).foregroundStyle(path.underruns > 0 ? .orange : .primary)
                    Text("\(path.overflows)").frame(width: 60, alignment: .trailing).foregroundStyle(path.overflows > 0 ? .orange : .primary)
                    Text(ms(path.latency)).frame(width: 170, alignment: .trailing)
                }.font(.caption.monospaced())
            }
        }
    }
}

// MARK: - Macro buttons and scenes

struct MacroButtonsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var localization = LocalizationStore.shared
    @State private var editing: UUID?
    @State private var newSceneName = ""
    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.text("マクロボタン")).font(.headline)
                    Spacer()
                    Button(L10n.text("＋ ボタン")) { state.addMacroButton() }.disabled(state.macroButtons.count >= 64)
                }
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(state.macroButtons) { button in macroTile(button) }
                    }
                }
                if let id = editing, state.macroButtons.contains(where: { $0.id == id }) {
                    MacroEditor(state: state, id: id) { editing = nil }
                } else {
                    Text(L10n.text("右クリックで編集。スクリプト例: Strip[0].A1 = 1; Strip[3].Mute = toggle; Bus[1].Gain -= 3; Scene = \"配信\"。番号は表示中の並び（ハードウェア入力→VAIO→AUX、A1〜→B1→B2）で0から数えます。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(14).frame(minWidth: 560)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("シーン")).font(.headline)
                HStack {
                    TextField(L10n.text("新しいシーン名"), text: $newSceneName)
                    Button(L10n.text("現在の状態を保存")) { state.saveScene(name: newSceneName); newSceneName = "" }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(state.scenes) { scene in sceneRow(scene) }
                    }
                }
                HStack {
                    Button(L10n.text("書き出し…")) { state.exportMacroLibrary() }
                    Button(L10n.text("読み込み…")) { state.importMacroLibrary() }
                }
                Text(L10n.text("シーンはルーティング・音量・EQ等をまとめて保存し、ボタン・MIDI・マクロ（Scene = \"名前\"）から呼び出せます。デバイスとチャンネル割り当ては変更しません。"))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(14).frame(minWidth: 400)
        }
        .id(localization.language)
        .background(VMTheme.consoleBg)
    }

    private func color(_ color: MacroColor) -> Color {
        switch color {
        case .blue: return .blue; case .green: return .green; case .orange: return .orange
        case .red: return .red; case .purple: return .purple; case .gray: return .gray
        }
    }
    private func macroTile(_ button: MacroButton) -> some View {
        let lit = button.mode != .push && button.isOn
        return MacroPad(title: button.name, subtitle: button.shortcut?.displayName ?? (button.group.map { "G\($0)" } ?? ""),
                        color: color(button.color), lit: lit, selected: editing == button.id,
                        down: { state.macroButton(button.id, down: true) }, up: { state.macroButton(button.id, down: false) },
                        edit: { editing = editing == button.id ? nil : button.id })
            .frame(height: 54)
    }
    private func sceneRow(_ scene: MixerScene) -> some View {
        let active = state.activeSceneID == scene.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("", text: Binding(get: { scene.name }, set: { name in state.updateScene(scene.id) { $0.name = name } })).font(.body.bold())
                Button(L10n.text("呼出")) { state.recallScene(scene.id) }.buttonStyle(.borderedProminent).tint(active ? .orange : .accentColor)
                Button(L10n.text("上書き")) { state.saveScene(name: scene.name, replacing: scene.id) }
                Button { state.deleteScene(scene.id) } label: { Image(systemName: "trash") }
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 2) {
                scopeToggle(scene, L10n.text("ルーティング"), \.routing)
                scopeToggle(scene, L10n.text("音量"), \.levels)
                scopeToggle(scene, "Mute/Solo", \.mutes)
                scopeToggle(scene, "EQ", \.eq)
                scopeToggle(scene, L10n.text("ダイナミクス等"), \.dynamics)
                scopeToggle(scene, "INSERT", \.inserts)
            }.font(.caption)
        }
        .padding(8)
        .background(active ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
    private func scopeToggle(_ scene: MixerScene, _ title: String, _ key: WritableKeyPath<SceneScope, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { scene.scope[keyPath: key] }, set: { value in state.updateScene(scene.id) { $0.scope[keyPath: key] = value } }))
            .toggleStyle(.checkbox).fixedSize()
    }
}

/// Press/release-aware pad (momentary macros need the release).
private struct MacroPad: NSViewRepresentable {
    let title: String, subtitle: String
    let color: Color
    let lit: Bool, selected: Bool
    let down: () -> Void, up: () -> Void, edit: () -> Void
    func makeNSView(context: Context) -> Pad { Pad() }
    func updateNSView(_ view: Pad, context: Context) {
        view.down = down; view.up = up; view.edit = edit
        let base = NSColor(color)
        view.layer?.backgroundColor = (lit ? base : base.withAlphaComponent(0.22)).cgColor
        view.layer?.borderColor = (selected ? NSColor.white : base).cgColor
        view.layer?.borderWidth = selected ? 2 : 1
        view.label.attributedStringValue = NSAttributedString(string: title + (subtitle.isEmpty ? "" : "\n" + subtitle), attributes: [
            .font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: lit ? NSColor.black : NSColor.white])
        view.setAccessibilityLabel(title); view.setAccessibilityValue(lit ? "ON" : "OFF")
    }
    final class Pad: NSView {
        var down: (() -> Void)?, up: (() -> Void)?, edit: (() -> Void)?
        let label = NSTextField(labelWithString: "")
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true; layer?.cornerRadius = 6
            label.alignment = .center; label.maximumNumberOfLines = 2; label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: centerXAnchor), label.centerYAnchor.constraint(equalTo: centerYAnchor),
                                         label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -8)])
            setAccessibilityElement(true); setAccessibilityRole(.button)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { down?() }
        override func mouseUp(with event: NSEvent) { up?() }
        override func rightMouseDown(with event: NSEvent) { edit?() }
        override func accessibilityPerformPress() -> Bool { down?(); up?(); return true }
    }
}

private struct MacroEditor: View {
    @ObservedObject var state: AppState
    let id: UUID
    let close: () -> Void
    private var button: MacroButton { state.macroButtons.first { $0.id == id } ?? MacroButton() }
    private func binding<T>(_ key: WritableKeyPath<MacroButton, T>) -> Binding<T> {
        Binding(get: { button[keyPath: key] }, set: { value in state.updateMacroButton(id) { $0[keyPath: key] = value } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(L10n.text("名前"), text: binding(\.name)).frame(width: 140)
                Picker("", selection: binding(\.mode)) { ForEach(MacroButtonMode.allCases, id: \.self) { Text($0.name).tag($0) } }.labelsHidden().frame(width: 150)
                Picker("", selection: binding(\.color)) { ForEach(MacroColor.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 80)
                Spacer(minLength: 0)
                Button { state.moveMacroButton(id, by: -1) } label: { Image(systemName: "arrow.left") }
                Button { state.moveMacroButton(id, by: 1) } label: { Image(systemName: "arrow.right") }
                Button(role: .destructive) { state.deleteMacroButton(id); close() } label: { Image(systemName: "trash") }
                Button(L10n.text("閉じる"), action: close)
            }
            HStack {
                Text(L10n.text("グループ")).font(.caption)
                Picker("", selection: Binding(get: { button.group ?? 0 }, set: { value in state.updateMacroButton(id) { $0.group = value == 0 ? nil : value } })) {
                    Text(L10n.text("なし")).tag(0)
                    ForEach(1...8, id: \.self) { Text("G\($0)").tag($0) }
                }.labelsHidden().frame(width: 80).disabled(button.mode != .toggle)
                Text(L10n.text("キー")).font(.caption)
                ShortcutRecorder(shortcut: binding(\.shortcut)).frame(width: 130, height: 24)
                Spacer(minLength: 0)
            }.font(.caption)
            HStack {
                Button(L10n.text("MIDI Learn")) {
                    var mapping = MIDIMapping(target: midiMacroTarget, parameter: .macroButton); mapping.macroID = id
                    state.midiMappings.append(mapping); state.saveSettings(); state.midiLearnMappingID = mapping.id
                }
                Button(L10n.text("今の状態をシーン化")) {
                    let scene = state.saveScene(name: button.name)
                    let name = state.scenes.first { $0.id == scene }?.name ?? button.name
                    state.updateMacroButton(id) { $0.onScript = "Scene = \"\(name)\"" }
                }
                Spacer(minLength: 0)
            }.font(.caption)
            Text(button.mode == .push ? L10n.text("押したとき") : L10n.text("ONにしたとき")).font(.caption)
            TextEditor(text: binding(\.onScript)).font(.system(size: 11, design: .monospaced)).frame(height: 60)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
            if button.mode != .push {
                Text(L10n.text("OFFにしたとき")).font(.caption)
                TextEditor(text: binding(\.offScript)).font(.system(size: 11, design: .monospaced)).frame(height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
            }
            let errors = MacroScript.parse(button.onScript).errors + MacroScript.parse(button.offScript).errors
            if let first = errors.first {
                Text(L10n.text("{0}行目: {1}", [String(first.line), first.message])).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(8).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}
