import SwiftUI
import AppKit
import ServiceManagement

struct AudioSettingsView: View {
    @ObservedObject private var localization = LocalizationStore.shared
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showBusOrder = false
    @State private var rate: Double = 48000
    @State private var buffer: UInt32 = 256
    @State private var meters: Double = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(L10n.text("オーディオ設定")).font(.title2.bold())
                Spacer()
                Button(L10n.text("閉じる")) { dismiss() }
            }
            Text(L10n.text("マスタークロック: {0}", [L10n.text(appState.masterA1DeviceName)])).font(.callout)
            Picker("言語 / Language", selection: Binding(get: { localization.language }, set: localization.select)) {
                Text("日本語").tag("ja")
                Text("English").tag("en")
            }.pickerStyle(.segmented).frame(width: 260)
            TabView {
                VStack(alignment: .leading, spacing: 12) {
            Toggle(L10n.text("同じバスに混ぜる入力のプラグイン遅延を自動補正"), isOn: Binding(get: { appState.latencyCompensationEnabled }, set: appState.setLatencyCompensation))
            Toggle(L10n.text("デバイス切断・音声停止時に自動復旧"), isOn: Binding(get: { appState.automaticDeviceRestart }, set: appState.setAutomaticDeviceRestart))
            Toggle(L10n.text("Macログイン時に自動起動"), isOn: Binding(get: { appState.launchAtLogin || appState.loginApprovalRequired }, set: appState.setLaunchAtLogin))
            if appState.loginApprovalRequired {
                Button(L10n.text("システム設定でログイン項目を許可")) { SMAppService.openSystemSettingsLoginItems() }
            }
            Button(L10n.text("信号順序")) { showBusOrder = true }
            Form {
                Picker(L10n.text("サンプルレート"), selection: $rate) {
                    ForEach([44100.0, 48000, 88200, 96000, 176400, 192000], id: \.self) { value in
                        Text("\(Int(value)) Hz").tag(value)
                    }
                }
                Picker(L10n.text("バッファサイズ"), selection: $buffer) {
                    ForEach([UInt32(32), 64, 128, 256, 512, 1024, 2048, 4096], id: \.self) { value in
                        Text("\(value) samples").tag(value)
                    }
                }
                Picker(L10n.text("メーター更新頻度"), selection: $meters) {
                    ForEach([15.0, 30, 60], id: \.self) { value in Text("\(Int(value)) fps").tag(value) }
                }
            }
                    Text(L10n.text("Cubase: 更新済みのAudiomeeterを1つ選択すると、再生はVAIO、録音はB1になります。Audiomeeter AUXを選ぶと再生はAUX、録音はB2になります。DAWモニターはVAIO → A1、PC音声の録音はAUX → B1。VAIO → B1は録音ループになるためOFFにしてください。"))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(12).tabItem { Text(L10n.text("エンジン")) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.text("左右の物理チャンネルを個別に選択できます。変更はすぐ反映されます。同じ出力チャンネルに左右を割り当てるとモノラルに合成します。"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(L10n.text("入力チャンネル")).font(.headline)
                        ForEach(StripID.allCases) { strip in
                            let device = appState.inputDevices.first { $0.uid == appState.strips[strip]?.deviceUID }
                            channelRow(name: strip.shortName, device: device?.name, count: device?.inChannels ?? 0,
                                       left: Binding(get: { appState.strips[strip]?.leftChannel ?? appState.strips[strip]?.channelOffset ?? 0 }, set: { appState.setStripChannel(strip: strip, left: true, channel: $0) }),
                                       right: Binding(get: { appState.strips[strip]?.rightChannel ?? min((appState.strips[strip]?.channelOffset ?? 0) + 1, max(0, (device?.inChannels ?? 1) - 1)) }, set: { appState.setStripChannel(strip: strip, left: false, channel: $0) }))
                        }
                        Divider()
                        Text(L10n.text("出力チャンネル")).font(.headline)
                        ForEach(BusID.allCases) { bus in
                            let device = appState.outputDevices.first { $0.uid == appState.buses[bus]?.deviceUID }
                            channelRow(name: bus.name, device: device?.name, count: device?.outChannels ?? 0,
                                       left: Binding(get: { appState.buses[bus]?.leftChannel ?? appState.buses[bus]?.channelOffset ?? 0 }, set: { appState.setBusChannel(bus: bus, left: true, channel: $0) }),
                                       right: Binding(get: { appState.buses[bus]?.rightChannel ?? min((appState.buses[bus]?.channelOffset ?? 0) + 1, max(0, (device?.outChannels ?? 1) - 1)) }, set: { appState.setBusChannel(bus: bus, left: false, channel: $0) }))
                        }
                    }.padding(12)
                }.tabItem { Text(L10n.text("チャンネル割り当て")) }
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(L10n.text("出力バス同士のプラグイン遅延を揃える"), isOn: Binding(get: { appState.outputBusAlignmentEnabled }, set: appState.setOutputBusAlignment))
                    Text(L10n.text("ON: A1〜B2の出力を最も遅い経路に揃えます。OFF: 無関係なバスのプラグインによる追加ディレイを止めます。同じバスに混ぜる入力の補正とサイドチェイン同期は、それぞれの設定に従います。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(L10n.text("サイドチェインと本線の時刻を揃える"), isOn: Binding(get: { appState.sidechainAlignmentEnabled }, set: appState.setSidechainAlignment))
                    Text(L10n.text("ON: 遅い経路に合わせて本線またはサイドチェインにディレイを追加。OFF: 本線には同期用ディレイを追加しません。循環接続は1ブロック前の信号を使い、同期の対象外になります。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(L10n.text("補正にはプラグイン＋プロセス通信の遅延が含まれます。機器固有の遅延は、各バスに追加ディレイを設定して調整してください。"))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(BusID.allCases) { bus in
                        HStack {
                            Text(bus.name).frame(width: 28)
                            Slider(value: Binding(get: { appState.buses[bus]?.delayMilliseconds ?? 0 }, set: { appState.setBusDelay(bus: bus, milliseconds: $0) }), in: 0...500)
                            Text(String(format: "%.1f ms", appState.buses[bus]?.delayMilliseconds ?? 0)).monospacedDigit().frame(width: 70)
                            Button(L10n.text("Reset")) { appState.setBusDelay(bus: bus, milliseconds: 0) }
                        }
                    }
                }.padding(12).tabItem { Text(L10n.text("遅延補正")) }
                DesktopControlsSettingsView(state: appState).tabItem { Text(L10n.text("キー・常駐表示")) }
                MIDISettingsView(state: appState, monitor: appState.midiMonitor).tabItem { Text("MIDI") }
            }.frame(height: 395)
            Text(String(format: L10n.text("1ブロック: %.2f ms • 現在: %.0f Hz / %d samples"), Double(buffer) / rate * 1000, appState.engineSampleRate, appState.engineBufferSize))
                .font(.system(.caption, design: .monospaced))
            Text(L10n.text("設定はA1のデバイスへ適用されます。対応値はデバイスにより異なり、適用中は音声が一時停止します。表示の時間にはデバイス・クロック補正・プラグインの遅延は含まれません。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L10n.text("デバイスを再検索")) { appState.rescanDevices() }
                Button(L10n.text("エンジンを再起動")) { appState.restartAudioEngine() }
                Spacer()
                Button(L10n.text("適用")) { appState.applyAudioSettings(rate: rate, frames: buffer, meters: meters) }
                    .buttonStyle(.borderedProminent).disabled(appState.recorderPlayer.isRecording)
            }
        }
        .id(localization.language)
        .padding(24).frame(width: 560)
        .sheet(isPresented: $showBusOrder) { BusOrderSettingsView(appState: appState) }
        .onAppear { rate = appState.engineSampleRate; buffer = appState.engineBufferSize; meters = appState.meterRefreshRate }
    }
    private func channelRow(name: String, device: String?, count: Int, left: Binding<Int>, right: Binding<Int>) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                Text(device.map { "\($0) · \(count) ch" } ?? L10n.text("デバイス未選択")).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Picker(L10n.text("左 L"), selection: left) {
                ForEach(0..<max(1, count), id: \.self) { Text("\($0 + 1)").tag($0) }
            }.frame(width: 120)
            Picker(L10n.text("右 R"), selection: right) {
                ForEach(0..<max(1, count), id: \.self) { Text("\($0 + 1)").tag($0) }
            }.frame(width: 120)
        }.disabled(count == 0 || appState.isStartingAudio)
    }

}

struct InsertRackView: View {
    @State private var showingPicker = false
    @State private var selectedPosition: InsertPosition = .pre
    @ObservedObject var appState: AppState
    let target: InsertTarget
    @Environment(\.dismiss) private var dismiss

    private func latencyText(_ samples: Int) -> String {
        String(format: "%d samples (%.2f ms)", samples, Double(samples) / max(1, appState.engineSampleRate) * 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(target.name) • VST3 INSERTS").font(.title2.bold())
                Spacer()
                Toggle("ON", isOn: Binding(get: { appState.insertChainIsEnabled(target) }, set: { _ in appState.toggleInsertChain(target) })).toggleStyle(.switch)
                Button(L10n.text("閉じる")) { appState.capturePluginStates(); dismiss() }
            }
            Text(L10n.text("PRE → EQ／ダイナミクス／フェーダー → POST → 遅延補正")).font(.caption.monospaced())
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(InsertPosition.allCases, id: \.self) { position in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(position.rawValue) FADER").font(.headline)
                                Spacer()
                                Button(L10n.text("＋ VST3を挿入")) { selectedPosition = position; showingPicker = true }.disabled(!appState.pluginHostingAvailable)
                            }
                            let slots = (appState.insertConfigs[target] ?? []).filter { $0.position == position }
                            if slots.isEmpty { Text(L10n.text("インサートなし")).font(.caption).foregroundStyle(.secondary) }
                            ForEach(slots) { slot in
                                VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Toggle("", isOn: Binding(get: { !slot.bypassed }, set: { appState.changeInsert(target: target, id: slot.id, bypass: !$0) }))
                                        .labelsHidden().help(L10n.text("有効／バイパス"))
                                    Text(slot.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    Button(L10n.text("編集")) { appState.editInsert(target: target, id: slot.id) }
                                    Button("↑") { appState.changeInsert(target: target, id: slot.id, move: -1) }
                                    Button("↓") { appState.changeInsert(target: target, id: slot.id, move: 1) }
                                    Button(role: .destructive) { appState.changeInsert(target: target, id: slot.id, remove: true) } label: { Image(systemName: "trash") }
                                }
                                if (appState.insertSideChannels[slot.id] ?? 0) > 0 {
                                    Picker(L10n.text("サイドチェイン"), selection: Binding<Int>(get: { slot.sidechainBus.map { 100 + $0.rawValue } ?? slot.sidechain?.rawValue ?? -1 }, set: { source in
                                        appState.setInsertSidechain(target: target, id: slot.id, strip: source >= 0 && source < 100 ? StripID(rawValue: source) : nil, bus: source >= 100 ? BusID(rawValue: source - 100) : nil)
                                    })) {
                                        Text(L10n.text("未設定（無音）")).tag(-1)
                                        ForEach(StripID.allCases) { strip in Text(strip.shortName).tag(strip.rawValue) }
                                        ForEach(BusID.allCases) { bus in Text(bus.name).tag(100 + bus.rawValue) }
                                    }
                                    if let bus = slot.sidechainBus {
                                        let feedback = appState.sidechainUsesPreviousBlock(target: target, bus: bus)
                                        Text(feedback ? L10n.text("循環接続: 1ブロック前（{0}）・同期対象外", [String(describing: latencyText(Int(appState.engineBufferSize)))]) : L10n.text("同じブロックのバス出力を使用"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if appState.sidechainAlignmentEnabled && !slot.bypassed {
                                        Text(L10n.text("本線への同期ディレイ: {0}", [String(describing: latencyText(appState.insertAlignmentDelays[slot.id] ?? 0))]))
                                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                                if let status = appState.insertStatus[slot.id], !status.isEmpty {
                                    HStack { Text(status).font(.caption).foregroundStyle(.secondary); Spacer(); Button(L10n.text("再読込")) { appState.retryInsert(target: target, id: slot.id) } }
                                }
                                }
                                .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
            Text(L10n.text("プラグイン遅延: {0} / 同期ディレイ: {1} / 経路補正: {2}", [String(describing: latencyText(appState.insertLatencies[target] ?? 0)), String(describing: latencyText(appState.sidechainAlignmentSamples(target: target))), String(describing: latencyText(appState.compensationSamples(target: target)))]))
                .font(.caption.monospaced())
            Text(L10n.text("サイドチェイン: 入力はPREインサート前、バスはインサート・フェーダー・追加ディレイ後／最終出力の自動補正前。循環接続のみ前のブロックを使用します。各プラグインのプロセス通信には別途1ブロックの遅延があります。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 640, height: 480)
        .sheet(isPresented: $showingPicker) {
            PluginPickerView { entry in
                showingPicker = false
                appState.addInsert(target: target, position: selectedPosition, path: entry.path, identifier: entry.identifier)
            } manualSelection: {
                showingPicker = false
                selectPlugin(selectedPosition)
            }
        }
    }

    private func selectPlugin(_ position: InsertPosition) {
        let panel = NSOpenPanel()
        panel.title = L10n.text("ARM64 VST3エフェクトを選択")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard url.pathExtension.lowercased() == "vst3" else { appState.audioError = L10n.text(".vst3プラグインを選択してください。"); return }
            appState.addInsert(target: target, position: position, path: url.path)
        }
    }
}

struct AppTrimView: View {
    @ObservedObject var appState: AppState
    let strip: StripID
    @Environment(\.dismiss) private var dismiss
    private var items: [AppVolumeItem] { strip == .virtualVAIO ? appState.vaioAppVolumes : appState.auxAppVolumes }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.text("{0} • アプリ別トリム", [String(describing: strip.shortName)])).font(.title2.bold())
                Spacer()
                Button(L10n.text("閉じる")) { dismiss() }
            }
            if appState.appTrimSupported[strip] != true {
                Text(appState.appTrimErrors[strip] ?? L10n.text("アプリ別トリムを確認中です。"))
            } else if items.isEmpty {
                Text(L10n.text("このデバイスに出力中のアプリがありません。")).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    ForEach(items) { item in
                        HStack {
                            Text(item.name).frame(width: 160, alignment: .leading).lineLimit(1)
                            Slider(value: Binding(get: { Double(item.volume > 0 ? 20 * log10(item.volume) : -60) }, set: { appState.setAppTrim(strip: strip, pid: item.pid, gain: $0 <= -60 ? 0 : pow(10, Float($0) / 20)) }), in: -60...6)
                            Text(item.volume == 0 ? L10n.text("Mute") : String(format: "%+.1f dB", 20 * log10(item.volume)))
                                .font(.caption.monospaced()).frame(width: 70)
                            Button(L10n.text("Reset")) { appState.setAppTrim(strip: strip, pid: item.pid, gain: 1) }
                        }.padding(.vertical, 6)
                    }
                }
            }
            Text(L10n.text("混合前のアプリ音声に適用 • −60 dBでミュート • 一覧は1秒ごとに更新\nブラウザ等の複数タブはCore Audioに接続しているプロセス単位で表示されます。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 600, height: 330)
    }

}
