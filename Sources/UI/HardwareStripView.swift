import SwiftUI

/// Channel Strip for Hardware Inputs (Strips 1, 2, 3)
public struct HardwareStripView: View {
    @State private var showInserts = false
    public let stripID: StripID
    @ObservedObject public var appState: AppState

    public init(stripID: StripID, appState: AppState) {
        self.stripID = stripID
        self.appState = appState
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
                // Intellipan 2D Pad
                IntellipanPadView(
                    state: Binding(
                        get: { settings.intellipan },
                        set: { appState.setStripIntellipan(strip: stripID, x: $0.x, y: $0.y) }
                    ),
                    size: 58
                )

                // Dynamics Knobs (Comp & Gate)
                HStack(spacing: 8) {
                    RotaryKnobView(
                        title: "COMP",
                        value: Binding(
                            get: { settings.dynamics.compKnob },
                            set: { appState.setStripDynamics(strip: stripID, comp: $0) }
                        ),
                        range: 0.0...10.0,
                        defaultValue: 0.0
                    )
                    RotaryKnobView(
                        title: "GATE",
                        value: Binding(
                            get: { settings.dynamics.gateKnob },
                            set: { appState.setStripDynamics(strip: stripID, gate: $0) }
                        ),
                        range: 0.0...10.0,
                        defaultValue: 0.0
                    )
                }

            DualActionButton(title: "INSERTS • \((appState.insertConfigs[.strip(stripID)] ?? []).count) FX", isActive: appState.insertChainIsEnabled(.strip(stripID)), onLeftClick: { appState.toggleInsertChain(.strip(stripID)) }, onRightClick: { showInserts = true }, fontSize: 9)
                .frame(height: 20)
                .sheet(isPresented: $showInserts) { InsertRackView(appState: appState, target: .strip(stripID)) }
                Spacer(minLength: 0)
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
            Text(L10n.text(stripID.name))
                .font(VMTheme.fontTitle)
                .foregroundColor(VMTheme.textPrimary)

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
                    Text(currentDevice?.name ?? L10n.text("Select Device..."))
                        .font(VMTheme.fontSmall)
                        .foregroundColor(currentDevice != nil ? VMTheme.textAccent : VMTheme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(VMTheme.textSecondary)
                }
                .padding(.horizontal, 4)
                .frame(height: 20)
                .background(VMTheme.hwHeaderBg)
                .cornerRadius(2)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(VMTheme.panelBorder, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
        }
    }
}
