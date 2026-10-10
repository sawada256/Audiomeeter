import SwiftUI
import AppKit

public struct SingleBusStripView: View {
    public let busID: BusID
    @ObservedObject public var appState: AppState
    @State private var showInserts = false
    @State private var showEQWindow = false
    @State private var showLimiter = false
    private var settings: BusSettings { appState.buses[busID] ?? BusSettings() }
    public init(busID: BusID, appState: AppState) { self.busID = busID; self.appState = appState }
    public var body: some View {
        VStack(spacing: 4) {
            Menu {
                ForEach(BusMode.allCases) { mode in
                    Button(mode.rawValue) { appState.setBusMode(bus: busID, mode: mode) }
                }
            } label: {
                Text(settings.mode.rawValue).font(VMTheme.fontSmall).frame(maxWidth: .infinity)
            }.menuStyle(.borderlessButton)
            LEDButton(label: "Mute", isActive: settings.isMuted, activeColor: VMTheme.ledMuteActive) { appState.toggleBusMute(bus: busID) }
            ForEach(appState.busProcessingOrder) { stage in
                switch stage {
                case .eq:
                    VStack(spacing: 2) {
                        EQButton(isActive: settings.isEQEnabled, onLeftClick: { appState.toggleBusEQ(bus: busID) }, onRightClick: { showEQWindow = true })
                        EQMiniCurve(config: settings.eqConfig, enabled: settings.isEQEnabled, sampleRate: Float(appState.engineSampleRate))
                            .frame(height: 29).contentShape(Rectangle()).onTapGesture { showEQWindow = true }
                            .accessibilityLabel("EQ Preview").accessibilityAddTraits(.isButton)
                    }
                case .preInserts, .postInserts:
                    insertPreview(position: stage == .preInserts ? .pre : .post)
                case .fader:
                    HStack(spacing: 2) {
                        Rectangle().frame(height: 1)
                        Text("FADER").font(.system(size: 7, weight: .semibold)).fixedSize()
                        Rectangle().frame(height: 1)
                    }.foregroundStyle(VMTheme.textSecondary).frame(height: 10)
                case .limiter:
                    LiveLimiterButton(meters: appState.meterStore, bus: busID, enabled: settings.isLimiterEnabled ?? true,
                                      toggle: { appState.setBusLimiter(bus: busID, enabled: !(settings.isLimiterEnabled ?? true)) },
                                      edit: { showLimiter = true })
                }
            }
            Spacer(minLength: 4)
            HStack(alignment: .top, spacing: 4) {
                FaderSliderView(gainDB: Binding(get: { settings.gainDB }, set: { appState.setBusGain(bus: busID, gainDB: $0) }),
                                height: MixerLayout.faderHeight, scrollStep: appState.desktopControls.gainStep,
                                reverseTrackpadScroll: appState.desktopControls.reverseTrackpadScroll ?? true,
                                reverseMouseScroll: appState.desktopControls.reverseMouseScroll ?? true)
                LiveVUMeterView(meters: appState.meterStore, target: .bus(busID), height: MixerLayout.faderHeight)
            }
        }.padding(.horizontal, 4).padding(.top, 4).frame(width: 82).frame(maxHeight: .infinity)
            .background(LinearGradient(colors: [VMTheme.stripBgTop, VMTheme.stripBgBottom], startPoint: .top, endPoint: .bottom))
            .overlay(Rectangle().stroke(VMTheme.panelBorder.opacity(0.7), lineWidth: 1))
            .sheet(isPresented: $showEQWindow) { EQWindowView(appState: appState, bus: busID, onClose: { showEQWindow = false }) }
            .sheet(isPresented: $showInserts) { InsertRackView(appState: appState, target: .bus(busID)) }
            .sheet(isPresented: $showLimiter) { LimiterSettingsView(appState: appState, bus: busID) }
    }

    private func insertPreview(position: InsertPosition) -> some View {
        let slots = (appState.insertConfigs[.bus(busID)] ?? []).filter { $0.position == position }
        return VStack(spacing: 2) {
            DualActionButton(title: "\(position.rawValue) INSERTS · \(slots.count)", isActive: appState.insertChainIsEnabled(.bus(busID)),
                             onLeftClick: { appState.toggleInsertChain(.bus(busID)) }, onRightClick: { showInserts = true }, fontSize: 7)
                .frame(height: 20).help(L10n.text("左クリック: ON/OFF、右クリック: 編集"))
            ScrollView(.vertical, showsIndicators: slots.count > 2) {
                VStack(spacing: 2) {
                    if slots.isEmpty { Text("—").font(VMTheme.fontSmall).foregroundStyle(.secondary).frame(height: 16) }
                    ForEach(slots, id: \.id) { slot in
                        DualActionButton(title: slot.name, isActive: !slot.bypassed,
                                         onLeftClick: { appState.changeInsert(target: .bus(busID), id: slot.id, bypass: !slot.bypassed) },
                                         onRightClick: { appState.editInsert(target: .bus(busID), id: slot.id) }, fontSize: 8)
                            .frame(height: 16).help(slot.name)
                    }
                }.padding(.horizontal, 2)
            }.frame(height: 34)
        }.padding(.bottom, 3)
            .background(VMTheme.textAccent.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(VMTheme.textAccent.opacity(0.22), lineWidth: 1))
    }
}

public struct MasterSectionView: View {
    @ObservedObject public var appState: AppState
    @State private var showOrder = false
    public init(appState: AppState) { self.appState = appState }
    public var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("MASTER SECTION").font(VMTheme.fontTitle)
                Spacer()
                Button { showOrder = true } label: { Image(systemName: "arrow.up.arrow.down") }
                    .buttonStyle(.plain).help(L10n.text("信号順序"))
            }
            HStack(alignment: .top, spacing: 2) {
                ForEach(BusID.allCases) { bus in
                    let device = appState.outputDevices.first { $0.uid == appState.buses[bus]?.deviceUID }
                    VStack(spacing: 2) {
                        Menu {
                            Button("None (Disabled)") { appState.setBusDevice(bus: bus, device: nil) }
                            Divider()
                            ForEach(appState.outputDevices) { item in Button(item.name) { appState.setBusDevice(bus: bus, device: item) } }
                        } label: {
                            Text(bus.name).font(VMTheme.fontTitle).frame(width: 66, height: 24)
                                .background(VMTheme.masterHeaderBg)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(VMTheme.panelBorder))
                        }.menuStyle(.borderlessButton)
                            .frame(width: 74, height: 26)
                            .background(VMTheme.masterHeaderBg)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(VMTheme.panelBorder, lineWidth: 1))
                        Text(device?.name ?? "None").font(.system(size: 8)).lineLimit(2)
                            .frame(height: 22, alignment: .top).frame(maxWidth: .infinity)
                            .help(device?.name ?? "None")
                    }.frame(width: 82).foregroundStyle(bus.isPhysical ? VMTheme.ledAActive : VMTheme.ledBActive)
                }
            }
            HStack(spacing: 2) {
                ForEach(BusID.allCases) { SingleBusStripView(busID: $0, appState: appState) }
            }.frame(maxHeight: .infinity)
        }.padding(6).frame(height: MixerLayout.stripHeight, alignment: .top).background(VMTheme.consoleBg)
            .overlay(Rectangle().stroke(VMTheme.panelBorder, lineWidth: 1))
            .sheet(isPresented: $showOrder) { BusOrderSettingsView(appState: appState) }
    }
}

struct EQMiniCurve: View {
    let config: MasterEQConfig
    let enabled: Bool
    var sampleRate: Float = 48000
    var body: some View {
        Canvas { context, size in
            var center = Path(); center.move(to: CGPoint(x: 0, y: size.height / 2)); center.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(center, with: .color(.gray.opacity(0.35)), lineWidth: 0.5)
            var curve = Path()
            for i in 0...80 {
                let frequency = 20 * powf(1000, Float(i) / 80)
                let db = ParametricEQ6Band.combinedResponseDB(config: config, freq: frequency, sampleRate: sampleRate)
                let point = CGPoint(x: size.width * CGFloat(i) / 80, y: size.height * (0.5 - CGFloat(min(24, max(-24, db))) / 48))
                if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            context.stroke(curve, with: .color(enabled ? VMTheme.textAccent : VMTheme.textSecondary), lineWidth: 1.2)
        }.background(VMTheme.grooveDark).overlay(Rectangle().stroke(VMTheme.panelBorder, lineWidth: 1))
    }
}

private struct LiveLimiterButton: View {
    @ObservedObject var meters: MixerMeterStore
    let bus: BusID
    let enabled: Bool
    let toggle: () -> Void
    let edit: () -> Void
    var body: some View {
        let reducing = enabled && (meters.frame.buses[bus]?.limiterReductionDB ?? 0) > 0.001
        TimelineView(.periodic(from: .now, by: 0.12)) { time in
            let red = reducing && Int(time.date.timeIntervalSince1970 / 0.12) % 2 == 0
            DualActionButton(title: "LIMIT", isActive: enabled, onLeftClick: toggle, onRightClick: edit,
                             activeColor: red ? .systemRed : .systemCyan)
        }.frame(height: 20)
    }
}

struct LimiterSettingsView: View {
    @ObservedObject var appState: AppState
    let bus: BusID
    @Environment(\.dismiss) private var dismiss
    private var settings: BusSettings { appState.buses[bus] ?? BusSettings() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(bus.name) · LIMIT").font(.headline)
            Text(L10n.text("先読みなしのソフトニー制限。Thresholdから圧縮し、Ceilingを超えないようにします。"))
                .font(.caption)
            HStack {
                Text("Threshold").frame(width: 80)
                Slider(value: Binding(get: { settings.limiterThresholdDB ?? -0.91515 }, set: { appState.setLimiterValues(bus: bus, threshold: $0, ceiling: settings.limiterCeilingDB ?? 0) }), in: -36...0)
                Text(String(format: "%.1f dB", settings.limiterThresholdDB ?? -0.91515)).frame(width: 65)
            }
            HStack {
                Text("Ceiling").frame(width: 80)
                Slider(value: Binding(get: { settings.limiterCeilingDB ?? 0 }, set: { appState.setLimiterValues(bus: bus, threshold: settings.limiterThresholdDB ?? -0.91515, ceiling: $0) }), in: -24...0)
                Text(String(format: "%.1f dB", settings.limiterCeilingDB ?? 0)).frame(width: 65)
            }
            HStack {
                Button("Reset") { appState.setLimiterValues(bus: bus, threshold: -0.91515, ceiling: 0) }
                Spacer(); Button(L10n.text("閉じる")) { dismiss() }
            }
        }.padding(24).frame(width: 450)
    }
}

struct BusOrderSettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    private func moved(_ index: Int, _ delta: Int) -> [BusProcessingStage] {
        var order = appState.busProcessingOrder
        guard order.indices.contains(index + delta) else { return [] }
        order.swapAt(index, index + delta); return order
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("出力バスの信号順序（全バス共通）")).font(.headline)
            Text(L10n.text("PRE → FADER → POSTの関係を保ち、EQとLIMITを移動できます。変更時は音声が一時停止します。"))
                .font(.caption)
            Picker("EQ Position", selection: Binding(get: { appState.busProcessingOrder.firstIndex(of: .eq) ?? 3 }, set: { index in
                var order = appState.busProcessingOrder.filter { $0 != .eq }
                order.insert(.eq, at: index)
                appState.setBusProcessingOrder(order)
            })) {
                let other = appState.busProcessingOrder.filter { $0 != .eq }
                ForEach(0..<5) { index in
                    Text("\(index == 0 ? "INPUT" : other[index - 1].title) → EQ → \(index == 4 ? "OUTPUT" : other[index].title)").tag(index)
                }
            }
            ForEach(Array(appState.busProcessingOrder.enumerated()), id: \.element) { index, stage in
                HStack {
                    Text(stage.title).frame(maxWidth: .infinity, alignment: .leading)
                    Button("↑") { appState.setBusProcessingOrder(moved(index, -1)) }.disabled(!BusProcessingStage.isValid(moved(index, -1)))
                    Button("↓") { appState.setBusProcessingOrder(moved(index, 1)) }.disabled(!BusProcessingStage.isValid(moved(index, 1)))
                }
            }
            HStack {
                Button("Reset") { appState.setBusProcessingOrder(BusProcessingStage.standard) }
                Spacer(); Button(L10n.text("閉じる")) { dismiss() }
            }
        }.padding(24).frame(width: 430)
    }
}

/// Native buttons receive secondary clicks directly, without a context-menu step.
struct DualActionButton: NSViewRepresentable {
    let title: String
    let isActive: Bool
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    var fontSize: CGFloat = 10
    var activeColor: NSColor = .systemCyan
    func makeNSView(context: Context) -> ActionButton { ActionButton() }
    func updateNSView(_ view: ActionButton, context: Context) {
        view.cell?.lineBreakMode = .byTruncatingTail
        view.title = title; view.left = onLeftClick; view.right = onRightClick
        view.font = .boldSystemFont(ofSize: fontSize)
        view.attributedTitle = NSAttributedString(string: title, attributes: [.font: view.font!, .foregroundColor: isActive ? NSColor.black : NSColor.systemCyan])
        view.layer?.backgroundColor = (isActive ? activeColor : NSColor(white: 0.12, alpha: 1)).cgColor
        view.layer?.borderColor = (isActive ? activeColor : NSColor(white: 0.25, alpha: 1)).cgColor
        view.toolTip = L10n.text("左クリック: ON/OFF、右クリック: 編集")
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
