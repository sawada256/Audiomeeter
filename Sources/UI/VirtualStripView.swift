import SwiftUI

/// Channel Strip for Virtual Inputs (Audiomeeter VAIO & AUX)
public struct VirtualStripView: View {
    public let stripID: StripID
    @State private var showAppTrims = false
    @State private var showInserts = false
    @ObservedObject public var appState: AppState

    public init(stripID: StripID, appState: AppState) {
        self.stripID = stripID
        self.appState = appState
    }

    private func hasEQPreset(_ slot: Int) -> Bool {
        guard let presets = appState.stripEQPresets[stripID.rawValue], presets.indices.contains(slot) else { return false }
        return presets[slot] != nil
    }

    private var settings: StripSettings {
        appState.strips[stripID] ?? StripSettings()
    }

    private var currentDevice: AudioDeviceInfo? {
        appState.inputDevices.first { $0.uid == settings.deviceUID }
    }

    private var meterLevel: MeterLevel {
        appState.stripMeters[stripID] ?? MeterLevel()
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Header with Device Selector
            headerView

            VStack(spacing: 3) {
                // 3-Band Equalizer (Bass, Med, Treble)
                VStack(spacing: 4) {
                    Menu {
                        ForEach(0..<3) { slot in
                            Button(L10n.text("プリセット{0}を呼出", [String(describing: slot + 1)])) { appState.loadStripEQPreset(strip: stripID, slot: slot) }
                                .disabled(!hasEQPreset(slot))
                            Button(L10n.text("現在のEQをプリセット{0}に保存", [String(describing: slot + 1)])) { appState.saveStripEQPreset(strip: stripID, slot: slot) }
                            if slot < 2 { Divider() }
                        }
                    } label: { Text(L10n.text("EQUALIZER")).font(VMTheme.fontLabel).foregroundColor(VMTheme.textSecondary) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help(L10n.text("3つのEQプリセットを保存・呼出"))

                    HStack(spacing: 4) {
                        RotaryKnobView(
                            title: L10n.text("BASS"),
                            value: Binding(
                                get: { settings.eq.lowGainDB },
                                set: { appState.setStripEQ(strip: stripID, low: $0) }
                            ),
                            range: -12.0...12.0,
                            defaultValue: 0.0,
                            unit: "dB",
                            isDB: true
                        )
                        RotaryKnobView(
                            title: L10n.text("MED"),
                            value: Binding(
                                get: { settings.eq.midGainDB },
                                set: { appState.setStripEQ(strip: stripID, mid: $0) }
                            ),
                            range: -12.0...12.0,
                            defaultValue: 0.0,
                            unit: "dB",
                            isDB: true
                        )
                        RotaryKnobView(
                            title: L10n.text("TREBLE"),
                            value: Binding(
                                get: { settings.eq.highGainDB },
                                set: { appState.setStripEQ(strip: stripID, high: $0) }
                            ),
                            range: -12.0...12.0,
                            defaultValue: 0.0,
                            unit: "dB",
                            isDB: true
                        )
                    }
                }
                .padding(.vertical, 4)

                // Karaoke / Center Cancel Button
                Button(action: {
                    appState.toggleStripKaraoke(strip: stripID)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.mic")
                            .font(.system(size: 9))
                        Text(L10n.text("KARAOKE (VOCAL CANCEL)"))
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(settings.isKaraoke ? Color.white : VMTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 18)
                    .background(settings.isKaraoke ? Color(red: 0.9, green: 0.15, blue: 0.45) : VMTheme.panelBackgroundDark)
                    .cornerRadius(2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(settings.isKaraoke ? Color(red: 1.0, green: 0.3, blue: 0.6) : VMTheme.panelBorder, lineWidth: 1)
                    )
                    .shadow(color: settings.isKaraoke ? Color(red: 0.9, green: 0.15, blue: 0.45).opacity(0.8) : Color.clear, radius: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 4)

                Button {
                    showAppTrims = true
                } label: {
                    Label("APPS", systemImage: "app.badge")
                        .font(VMTheme.fontSmallBold)
                }
                .buttonStyle(.plain)
                .foregroundStyle(VMTheme.textAccent)
                .help(L10n.text("この仮想デバイスに出力中のアプリとトリム"))
                .sheet(isPresented: $showAppTrims) { AppTrimView(appState: appState, strip: stripID) }
                DualActionButton(title: "INSERTS • \((appState.insertConfigs[.strip(stripID)] ?? []).count) FX", isActive: appState.insertChainIsEnabled(.strip(stripID)), onLeftClick: { appState.toggleInsertChain(.strip(stripID)) }, onRightClick: { showInserts = true }, fontSize: 9)
                    .frame(height: 20)
                    .sheet(isPresented: $showInserts) { InsertRackView(appState: appState, target: .strip(stripID)) }
                StereoPanView(appState: appState, strip: stripID)
            }
            .frame(height: MixerLayout.controlsHeight, alignment: .top)

            // Routing Matrix [A1] [A2] [A3] / [B1] [B2]
            RoutingButtonsView(routing: settings.routing) { bus in
                appState.toggleRouting(strip: stripID, bus: bus)
            }

            // Mute & Solo
            MuteSoloView(
                isMuted: settings.isMuted,
                isSolo: settings.isSolo,
                onToggleMute: { appState.toggleStripMute(strip: stripID) },
                onToggleSolo: { appState.toggleStripSolo(strip: stripID) }
            )

            Spacer(minLength: 0)

            // Fader & VU Meter
            HStack(alignment: .top, spacing: 6) {
                FaderSliderView(
                    gainDB: Binding(
                        get: { settings.gainDB },
                        set: { appState.setStripGain(strip: stripID, gainDB: $0) }
                    ),
                    height: MixerLayout.faderHeight,
                    scrollStep: appState.desktopControls.gainStep,
                    reverseTrackpadScroll: appState.desktopControls.reverseTrackpadScroll ?? true,
                    reverseMouseScroll: appState.desktopControls.reverseMouseScroll ?? true
                )
                LiveVUMeterView(meters: appState.meterStore, target: .strip(stripID), height: MixerLayout.faderHeight)
            }
            .padding(.top, 2)
        }
        .padding(6)
        .frame(width: 150, height: MixerLayout.stripHeight)
        .background(
            LinearGradient(
                colors: [VMTheme.stripBgTop, VMTheme.stripBgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .stroke(VMTheme.panelBorder.opacity(0.7), lineWidth: 1)
        )
    }

    private var headerView: some View {
        VStack(spacing: 2) {
            Text(stripID.name)
                .font(VMTheme.fontTitle)
                .foregroundColor(VMTheme.textGold)

            Menu {
                Button("None (Disabled)") {
                    appState.setStripDevice(strip: stripID, device: nil)
                }
                Divider()
                ForEach(appState.inputDevices) { dev in
                    Button(dev.name) {
                        appState.setStripDevice(strip: stripID, device: dev)
                    }
                }
            } label: {
                HStack {
                    Text(currentDevice?.name ?? L10n.text("Select Virtual In..."))
                        .font(VMTheme.fontSmall)
                        .foregroundColor(currentDevice != nil ? VMTheme.textGold : VMTheme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(VMTheme.textSecondary)
                }
                .padding(.horizontal, 4)
                .frame(height: 20)
                .background(VMTheme.virtualHeaderBg)
                .cornerRadius(2)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(VMTheme.panelBorder, lineWidth: 1)
                )
            }.menuStyle(.borderlessButton)
        }
    }
}
