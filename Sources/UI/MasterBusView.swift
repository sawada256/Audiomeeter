import SwiftUI

/// Single Master Bus Strip (A1, A2, A3, B1, B2)
public struct SingleBusStripView: View {
    public let busID: BusID
    @ObservedObject public var appState: AppState
    @State private var showInserts = false
    @State private var showEQWindow: Bool = false

    public init(busID: BusID, appState: AppState) {
        self.busID = busID
        self.appState = appState
    }

    private var settings: BusSettings {
        appState.buses[busID] ?? BusSettings()
    }

    private var currentDevice: AudioDeviceInfo? {
        appState.outputDevices.first { $0.uid == settings.deviceUID }
    }

    private var meterLevel: MeterLevel {
        appState.busMeters[busID] ?? MeterLevel()
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Bus Title
            Text(busID.name)
                .font(VMTheme.fontTitle)
                .foregroundColor(busID.isPhysical ? VMTheme.ledAActive : VMTheme.ledBActive)

            // Bus Mode selector (Normal / Mixdown / Mono)
            Menu {
                ForEach(BusMode.allCases) { mode in
                    Button(mode.rawValue) {
                        appState.setBusMode(bus: busID, mode: mode)
                    }
                }
            } label: {
                Text(settings.mode.rawValue)
                    .font(VMTheme.fontSmall)
                    .foregroundColor(VMTheme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 18)
                    .background(VMTheme.stripBgTop)
                    .cornerRadius(2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(VMTheme.panelBorder, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 2)

            // Mute & EQ Buttons Row
            HStack(spacing: 3) {
                // Mute Button
                LEDButton(label: "Mute", isActive: settings.isMuted, activeColor: VMTheme.ledMuteActive) {
                    appState.toggleBusMute(bus: busID)
                }

                // EQ Button: Left Click = Toggle On/Off, Right Click = Open EQ Window
                EQButton(
                    isActive: settings.isEQEnabled,
                    onLeftClick: {
                        appState.toggleBusEQ(bus: busID)
                    },
                    onRightClick: {
                        showEQWindow = true
                    }
                )
            }
            .padding(.horizontal, 2)
            .sheet(isPresented: $showEQWindow) {
                EQWindowView(appState: appState, bus: busID, onClose: {
                    showEQWindow = false
                })
            }

            DualActionButton(title: "INSERTS", isActive: appState.insertChainIsEnabled(.bus(busID)), onLeftClick: { appState.toggleInsertChain(.bus(busID)) }, onRightClick: { showInserts = true })
                .frame(height: 20)
                .sheet(isPresented: $showInserts) { InsertRackView(appState: appState, target: .bus(busID)) }
            Toggle("LIMIT", isOn: Binding(get: { settings.isLimiterEnabled ?? true }, set: { appState.setBusLimiter(bus: busID, enabled: $0) }))
                .toggleStyle(.button).font(VMTheme.fontSmall).help("低いレベルでは音を変えず、ピークを制限します")
            Text("\((appState.insertConfigs[.bus(busID)] ?? []).count) FX")
                .font(VMTheme.fontSmall).foregroundStyle(VMTheme.textSecondary)
            Spacer()

            // Fader & VU Meter
            HStack(alignment: .top, spacing: 4) {
                FaderSliderView(
                    gainDB: Binding(
                        get: { settings.gainDB },
                        set: { appState.setBusGain(bus: busID, gainDB: $0) }
                    ),
                    height: MixerLayout.faderHeight,
                    scrollStep: appState.desktopControls.gainStep,
                    reverseTrackpadScroll: appState.desktopControls.reverseTrackpadScroll ?? true,
                    reverseMouseScroll: appState.desktopControls.reverseMouseScroll ?? true
                )
                LiveVUMeterView(meters: appState.meterStore, target: .bus(busID), height: MixerLayout.faderHeight)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .frame(width: 82)
        .frame(maxHeight: .infinity)
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
}

/// Master Section containing Output device selectors (A1, A2, A3) and all 5 Output Bus Strips
public struct MasterSectionView: View {
    @ObservedObject public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Master Header & Physical Output Device Pickers
            headerDeviceSelectors

            // 5 Master Bus Strips
            HStack(spacing: 2) {
                SingleBusStripView(busID: .A1, appState: appState)
                SingleBusStripView(busID: .A2, appState: appState)
                SingleBusStripView(busID: .A3, appState: appState)
                SingleBusStripView(busID: .B1, appState: appState)
                SingleBusStripView(busID: .B2, appState: appState)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(6)
        .frame(height: MixerLayout.stripHeight, alignment: .top)
        .background(VMTheme.consoleBg)
        .overlay(
            Rectangle()
                .stroke(VMTheme.panelBorder, lineWidth: 1)
        )
    }

    private var headerDeviceSelectors: some View {
        VStack(spacing: 4) {
            HStack {
                Text("MASTER SECTION")
                    .font(VMTheme.fontTitle)
                    .foregroundColor(VMTheme.textPrimary)
                Spacer()
            }

            // A1, A2, A3 Dropdown selectors
            HStack(spacing: 4) {
                outputDeviceMenu(bus: .A1, label: "A1 (Master Clock)", color: VMTheme.ledAActive)
                outputDeviceMenu(bus: .A2, label: "A2 Out", color: VMTheme.ledAActive)
                outputDeviceMenu(bus: .A3, label: "A3 Out", color: VMTheme.ledAActive)
            }

            // B1, B2 Virtual Output selectors (for routing to OBS/Discord)
            HStack(spacing: 4) {
                outputDeviceMenu(bus: .B1, label: "B1 (VAIO Out)", color: VMTheme.ledBActive)
                outputDeviceMenu(bus: .B2, label: "B2 (AUX Out)", color: VMTheme.ledBActive)
            }
        }
        .padding(4)
        .background(VMTheme.masterHeaderBg.opacity(0.8))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(VMTheme.panelBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func outputDeviceMenu(bus: BusID, label: String, color: Color) -> some View {
        let currentUID = appState.buses[bus]?.deviceUID
        let currentDev = appState.outputDevices.first { $0.uid == currentUID }

        Menu {
            Button("None (Disabled)") {
                appState.setBusDevice(bus: bus, device: nil)
            }
            Divider()
            ForEach(appState.outputDevices) { dev in
                Button(dev.name) {
                    appState.setBusDevice(bus: bus, device: dev)
                }
            }
        } label: {
            Text("\(bus.name) · \(currentDev?.name ?? label)")
                .font(VMTheme.fontSmall)
                .foregroundColor(color)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .padding(.horizontal, 4)
                .background(VMTheme.stripBgTop)
                .cornerRadius(2)
                .help(currentDev?.name ?? label)
        }
        .menuStyle(.borderlessButton)
    }
}

/// Native buttons receive secondary clicks directly, without a context-menu step.
struct DualActionButton: NSViewRepresentable {
    let title: String
    let isActive: Bool
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    var fontSize: CGFloat = 10
    func makeNSView(context: Context) -> ActionButton { ActionButton() }
    func updateNSView(_ view: ActionButton, context: Context) {
        view.title = title; view.left = onLeftClick; view.right = onRightClick
        view.font = .boldSystemFont(ofSize: fontSize)
        view.attributedTitle = NSAttributedString(string: title, attributes: [.font: view.font!, .foregroundColor: isActive ? NSColor.black : NSColor.systemCyan])
        view.layer?.backgroundColor = (isActive ? NSColor.systemCyan : NSColor(white: 0.12, alpha: 1)).cgColor
        view.layer?.borderColor = (isActive ? NSColor.systemCyan : NSColor(white: 0.25, alpha: 1)).cgColor
        view.toolTip = "左クリック: ON/OFF、右クリック: 編集"
        view.setAccessibilityLabel(title); view.setAccessibilityValue(isActive ? "ON" : "OFF")
    }
    final class ActionButton: NSButton {
        var left: (() -> Void)?, right: (() -> Void)?
        init() {
            super.init(frame: .zero); setButtonType(.momentaryPushIn); isBordered = false
            wantsLayer = true; layer?.cornerRadius = 3; layer?.borderWidth = 1
            target = self; action = #selector(pressed)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        @objc private func pressed() { left?() }
        override func rightMouseDown(with event: NSEvent) { right?() }
    }
}
public struct EQButton: View {
    public let isActive: Bool
    public let onLeftClick: () -> Void
    public let onRightClick: () -> Void
    public var body: some View {
        DualActionButton(title: "EQ", isActive: isActive, onLeftClick: onLeftClick, onRightClick: onRightClick).frame(height: 20)
    }
}
