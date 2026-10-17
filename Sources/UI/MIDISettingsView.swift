import SwiftUI

/// MIDI controller assignment table (Voicemeeter "MIDI Mapping" / DAW "MIDI Learn").
struct MIDISettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var monitor: MIDIMonitor
    private var targets: [Int] {
        state.visibleStrips.map { InsertTarget.strip($0).id } + state.visibleBuses.map { InsertTarget.bus($0).id }
            + [midiRecorderTarget, midiPluginTarget, midiMacroTarget, midiSceneTarget]
    }

    private func mappingBinding<T>(_ id: UUID, _ key: WritableKeyPath<MIDIMapping, T>, fallback: T) -> Binding<T> {
        Binding(get: { state.midiMappings.first { $0.id == id }?[keyPath: key] ?? fallback },
                set: { value in state.updateMIDIMapping(id) { $0[keyPath: key] = value } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(L10n.text("MIDIコントローラーで操作する"), isOn: Binding(get: { state.midiEnabled }, set: state.setMIDIEnabled))
                Text(monitor.sources.isEmpty ? L10n.text("MIDI入力: 接続されたデバイスはありません") : L10n.text("MIDI入力: {0}", [monitor.sources.joined(separator: ", ")]))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("最後に受信: {0}", [monitor.lastMessage.isEmpty ? "—" : monitor.lastMessage]))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(L10n.text("「Learn」を押してからつまみ・フェーダー・ボタンを動かすと割り当てます。フェーダーの右クリックからも登録できます。ピックアップON: 絶対値のつまみが現在値に到達するまで反映せず、値の飛びを防ぎます。"))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(state.midiMappings) { mapping in row(mapping) }
                HStack {
                    Button(L10n.text("＋ 割り当てを追加")) { _ = state.addMIDIMapping() }
                        .disabled(state.midiMappings.count >= 256)
                    Spacer()
                    if state.midiLearnMappingID != nil { Button(L10n.text("Learnを中止")) { state.cancelMIDILearn() } }
                }
            }.padding(12)
        }
    }

    private func row(_ mapping: MIDIMapping) -> some View {
        let learning = state.midiLearnMappingID == mapping.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Picker(L10n.text("対象"), selection: mappingBinding(mapping.id, \.target, fallback: 100)) {
                    ForEach(targets, id: \.self) { Text(state.midiTargetName($0)).tag($0) }
                }.labelsHidden().frame(width: 90)
                targetDetail(mapping)
                Button(learning ? L10n.text("操作子を動かしてください…") : (mapping.trigger?.displayName ?? L10n.text("未割り当て"))) {
                    state.beginMIDILearn(mapping: mapping.id)
                }
                .frame(minWidth: 140)
                .help(L10n.text("クリックしてLearn。もう一度クリックで中止"))
                Spacer(minLength: 0)
                Button { state.removeMIDIMapping(mapping.id) } label: { Image(systemName: "trash") }
            }
            HStack(spacing: 10) {
                if mapping.parameter.isButton {
                    if mapping.parameter != .macroButton && mapping.parameter != .recallScene {
                        Picker(L10n.text("ボタン動作"), selection: mappingBinding(mapping.id, \.button, fallback: .toggle)) {
                            ForEach(MIDIButtonMode.allCases, id: \.self) { Text($0.name).tag($0) }
                        }.frame(width: 260)
                    }
                } else {
                    Picker(L10n.text("値の形式"), selection: mappingBinding(mapping.id, \.mode, fallback: .absolute)) {
                        ForEach(MIDIValueMode.allCases, id: \.self) { Text($0.name).tag($0) }
                    }.frame(width: 230)
                    Toggle(L10n.text("ピックアップ"), isOn: mappingBinding(mapping.id, \.pickup, fallback: true))
                        .disabled(mapping.mode != .absolute)
                }
                if mapping.target == midiPluginTarget {
                    Button(L10n.text("最後に操作したパラメーター")) { state.useLastTouchedParameter(mapping.id) }
                        .help(L10n.text("プラグインの画面で動かしたパラメーターを割り当てます"))
                }
            }.font(.caption)
        }
        .padding(8)
        .background(learning ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private func targetDetail(_ mapping: MIDIMapping) -> some View {
        switch mapping.target {
        case midiPluginTarget:
            Picker("", selection: Binding<UUID?>(get: { mapping.pluginInsertID }, set: { value in state.updateMIDIMapping(mapping.id) { $0.pluginInsertID = value; $0.pluginParameter = nil } })) {
                Text(L10n.text("プラグインを選択")).tag(UUID?.none)
                ForEach(state.midiPluginChoices, id: \.id) { Text($0.label).tag(UUID?.some($0.id)) }
            }.labelsHidden().frame(width: 150)
            Picker("", selection: Binding<Int>(get: { mapping.pluginParameter ?? -1 }, set: { value in state.updateMIDIMapping(mapping.id) { $0.pluginParameter = value < 0 ? nil : value } })) {
                Text(L10n.text("パラメーター")).tag(-1)
                ForEach(state.pluginParameters(mapping.pluginInsertID)) { Text($0.name.isEmpty ? "#\($0.index)" : $0.name).tag($0.index) }
            }.labelsHidden().frame(width: 150)
        case midiMacroTarget:
            Picker("", selection: Binding<UUID?>(get: { mapping.macroID }, set: { value in state.updateMIDIMapping(mapping.id) { $0.macroID = value } })) {
                Text(L10n.text("ボタンを選択")).tag(UUID?.none)
                ForEach(state.macroButtons) { Text($0.name).tag(UUID?.some($0.id)) }
            }.labelsHidden().frame(width: 200)
        case midiSceneTarget:
            Picker("", selection: Binding<UUID?>(get: { mapping.sceneID }, set: { value in state.updateMIDIMapping(mapping.id) { $0.sceneID = value } })) {
                Text(L10n.text("シーンを選択")).tag(UUID?.none)
                ForEach(state.scenes) { Text($0.name).tag(UUID?.some($0.id)) }
            }.labelsHidden().frame(width: 200)
        default:
            Picker(L10n.text("操作"), selection: mappingBinding(mapping.id, \.parameter, fallback: .gain)) {
                ForEach(MIDIControlParameter.available(for: mapping.target).filter { $0.routedBus.map(state.visibleBuses.contains) ?? true }, id: \.self) { Text($0.name).tag($0) }
            }.labelsHidden().frame(width: 130)
        }
    }
}
