import SwiftUI

/// Top-bar selector for the Mac's default output (what apps play to), with a one-tap
/// switch to Audiomeeter VAIO and back to the previous device.
struct SystemOutputControl: View {
    @ObservedObject var appState: AppState
    var body: some View {
        let current = appState.outputDevices.first { $0.id == appState.systemOutputDeviceID }
        HStack(spacing: 4) {
            Menu {
                ForEach(appState.systemOutputChoices) { device in
                    Button {
                        appState.setSystemOutput(device)
                    } label: {
                        if device.id == appState.systemOutputDeviceID { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text(L10n.text("Mac出力: {0}", [current?.name ?? "—"])).lineLimit(1).truncationMode(.tail)
                }
                .font(VMTheme.fontDigit).foregroundColor(VMTheme.textPrimary)
            }
            // Long device names truncate instead of pushing the VAIO button onto two lines.
            .menuStyle(.borderlessButton).frame(maxWidth: 220, alignment: .leading)
            .help(L10n.text("アプリの音の出力先（コントロールセンターの「サウンド」と同じ設定）"))
            Button { appState.toggleSystemOutputVAIO() } label: {
                Text("→ VAIO").font(VMTheme.fontDigit).lineLimit(1).fixedSize()
                    .foregroundColor(appState.systemOutputIsVAIO ? .black : VMTheme.textAccent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(appState.systemOutputIsVAIO ? VMTheme.textAccent : Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain).fixedSize()
            .help(appState.systemOutputIsVAIO ? L10n.text("もう一度押すと直前の出力先に戻します") : L10n.text("Macの出力先をAudiomeeter VAIOにします"))
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color.black.opacity(0.4)).cornerRadius(3)
    }
}

/// The macOS volume of the device on a physical bus. That volume is applied by the device
/// after Audiomeeter's mix, so this bar shows and adjusts the final trim.
struct DeviceVolumeBar: View {
    @ObservedObject var appState: AppState
    let bus: BusID
    var body: some View {
        if bus.isPhysical, let state = appState.busDeviceVolumes[bus] {
            if let volume = state.volume {
                HStack(spacing: 2) {
                    Button { appState.toggleBusDeviceMute(bus) } label: {
                        Image(systemName: state.muted == true ? "speaker.slash.fill" : volume < 0.01 ? "speaker.fill" : "speaker.wave.1.fill")
                            .font(.system(size: 8)).foregroundColor(state.muted == true || volume < 0.01 ? VMTheme.ledMuteActive : VMTheme.textSecondary)
                    }.buttonStyle(.plain).disabled(state.muted == nil)
                    Slider(value: Binding(get: { Double(volume) }, set: { appState.setBusDeviceVolume(bus, Float($0)) }), in: 0...1)
                        .controlSize(.mini)
                    Text("\(Int((volume * 100).rounded()))").font(.system(size: 7, design: .monospaced)).foregroundColor(VMTheme.textSecondary).frame(width: 16)
                }
                .help(L10n.text("Macの出力音量（このデバイスでの最終的な音量）。0%やミュートだとAudiomeeterの音も聞こえません。"))
            } else {
                Text(L10n.text("OS音量なし")).font(.system(size: 7)).foregroundColor(VMTheme.textSecondary)
                    .help(L10n.text("このデバイスにはmacOSの音量コントロールがありません。音量はフェーダーで調整します。"))
            }
        } else if bus.isVirtual {
            Text(L10n.text("フェーダーで調整")).font(.system(size: 7)).foregroundColor(VMTheme.textSecondary)
                .help(L10n.text("B1/B2のOS音量はVAIO/AUXと共通の設定で、通常は100%に維持されます。音量はB1/B2のフェーダーで調整してください。"))
        } else {
            Color.clear
        }
    }
}
