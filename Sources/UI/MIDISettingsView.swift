import SwiftUI

/// MIDI controller assignment table (Voicemeeter "MIDI Mapping" / DAW "MIDI Learn").
struct MIDISettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var monitor: MIDIMonitor
    private let targets = StripID.allCases.map { InsertTarget.strip($0).id } + BusID.allCases.map { InsertTarget.bus($0).id } + [midiRecorderTarget]

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
                Picker(L10n.text("操作"), selection: mappingBinding(mapping.id, \.parameter, fallback: .gain)) {
                    ForEach(MIDIControlParameter.available(for: mapping.target), id: \.self) { Text($0.name).tag($0) }
                }.labelsHidden().frame(width: 130)
                Button(learning ? L10n.text("操作子を動かしてください…") : (mapping.trigger?.displayName ?? L10n.text("未割り当て"))) {
                    state.beginMIDILearn(mapping: mapping.id)
                }
                .frame(minWidth: 150)
                .help(L10n.text("クリックしてLearn。もう一度クリックで中止"))
                Spacer(minLength: 0)
                Button { state.removeMIDIMapping(mapping.id) } label: { Image(systemName: "trash") }
            }
            HStack(spacing: 10) {
                if mapping.parameter.isButton {
                    Picker(L10n.text("ボタン動作"), selection: mappingBinding(mapping.id, \.button, fallback: .toggle)) {
                        ForEach(MIDIButtonMode.allCases, id: \.self) { Text($0.name).tag($0) }
                    }.frame(width: 260)
                } else {
                    Picker(L10n.text("値の形式"), selection: mappingBinding(mapping.id, \.mode, fallback: .absolute)) {
                        ForEach(MIDIValueMode.allCases, id: \.self) { Text($0.name).tag($0) }
                    }.frame(width: 230)
                    Toggle(L10n.text("ピックアップ"), isOn: mappingBinding(mapping.id, \.pickup, fallback: true))
                        .disabled(mapping.mode != .absolute)
                }
            }.font(.caption)
        }
        .padding(8)
        .background(learning ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
