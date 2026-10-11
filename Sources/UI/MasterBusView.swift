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
                    VStack(spacing: 0) {
                        EQButton(isActive: settings.isEQEnabled, onLeftClick: { appState.toggleBusEQ(bus: busID) }, onRightClick: { showEQWindow = true })
                        EQMiniCurve(config: settings.eqConfig, enabled: settings.isEQEnabled, sampleRate: Float(appState.engineSampleRate))
                            .frame(height: 29).contentShape(Rectangle()).onTapGesture { showEQWindow = true }
                            .accessibilityLabel("EQ Preview").accessibilityAddTraits(.isButton)
                    }.background(VMTheme.grooveDark).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                case .preInserts:
                    insertPreview
                case .postInserts, .fader:
                    EmptyView() // Both are represented inside the unified INSERT panel.
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

    private var faderBoundary: some View {
        HStack(spacing: 2) {
            Rectangle().frame(height: 1)
            Text("FADER").font(.system(size: 7, weight: .semibold)).fixedSize()
            Rectangle().frame(height: 1)
        }.foregroundStyle(VMTheme.textSecondary).frame(height: 10)
    }

    private func insertRow(_ slot: InsertConfig) -> some View {
        DualActionButton(title: slot.name, isActive: !slot.bypassed,
                         onLeftClick: { appState.changeInsert(target: .bus(busID), id: slot.id, bypass: !slot.bypassed) },
                         onRightClick: { appState.editInsert(target: .bus(busID), id: slot.id) }, fontSize: 8)
            .frame(height: 16).help("\(slot.position.rawValue) · \(slot.name)")
    }

    private var insertPreview: some View {
        let slots = appState.insertConfigs[.bus(busID)] ?? []
        let pre = slots.filter { $0.position == .pre }
        let post = slots.filter { $0.position == .post }
        let hasPost = !post.isEmpty
        // 3 × 16 pt rows + 2 × 2 pt gaps; POST consumes the 12 pt fader boundary reserve.
        return VStack(spacing: 2) {
            VStack(spacing: 2) {
                DualActionButton(title: "INSERT · \(slots.count)", isActive: appState.insertChainIsEnabled(.bus(busID)),
                                 onLeftClick: { appState.toggleInsertChain(.bus(busID)) }, onRightClick: { showInserts = true }, fontSize: 8)
                    .frame(height: 20)
                ScrollView(.vertical, showsIndicators: slots.count > 3) {
                    VStack(spacing: 2) {
                        if slots.isEmpty { Text("—").font(VMTheme.fontSmall).foregroundStyle(.secondary).frame(height: 16) }
                        ForEach(pre, id: \.id) { insertRow($0) }
                        if hasPost {
                            // Include intermediate stages so a moved EQ/LIMIT does not imply a false signal order.
                            ForEach(appState.busProcessingOrder.filter { stage in
                                guard let index = appState.busProcessingOrder.firstIndex(of: stage),
                                      let start = appState.busProcessingOrder.firstIndex(of: .preInserts),
                                      let end = appState.busProcessingOrder.firstIndex(of: .postInserts) else { return false }
                                return index > start && index < end
                            }) { stage in
                                if stage == .fader { faderBoundary }
                                else { Text(stage.title).font(.system(size: 7)).foregroundStyle(VMTheme.textSecondary).frame(height: 10) }
                            }
                            ForEach(post, id: \.id) { insertRow($0) }
                        }
                    }.padding(.horizontal, 2)
                }.frame(height: hasPost ? 64 : 52)
            }.background(VMTheme.textAccent.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(VMTheme.textAccent.opacity(0.22), lineWidth: 1))
            if !hasPost { faderBoundary }
        }.frame(height: 86, alignment: .top)
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
            let response = ParametricEQ6Band.responseCurve(config: config, sampleRate: sampleRate, points: 81)
            for i in 0...80 {
                let db = response[i]
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
        TimelineView(.animation(minimumInterval: 0.12, paused: !reducing)) { time in
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
            Text(L10n.text("先読みOFFはソフトニー波形制限。ONは左右連動のピーク検出と50 msリリースで音量を制御します。指定時間の遅延が加わります。True Peak制限ではありません。"))
                .font(.caption)
            Picker("Lookahead", selection: Binding(get: { settings.limiterLookaheadMS ?? 0 }, set: { appState.setLimiterLookahead(bus: bus, milliseconds: $0) })) {
                Text("Off · 0 ms").tag(0.0)
                ForEach([1.0,3,5,10,20],id:\.self) { Text("\(Int($0)) ms").tag($0) }
            }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("出力バスの信号順序（全バス共通）")).font(.headline)
            Picker("EQ Position", selection: Binding(get: { appState.busEQPosition }, set: { appState.setBusEQPosition($0) })) {
                ForEach(BusEQPosition.allCases, id: \.rawValue) { position in Text(position.title).tag(position) }
            }
            Text("PRE INSERT → FADER → POST INSERT → LIMIT").font(.caption.monospaced())
            Text(L10n.text("INSERTの後とLIMITの前は同じ位置です。EQはINSERT群の途中には入りません。変更時は音声が一時停止します。"))
                .font(.caption)
            HStack {
                Button("Reset") { appState.setBusEQPosition(.beforeLimiter) }
                Spacer(); Button(L10n.text("閉じる")) { dismiss() }
            }
        }.padding(24).frame(width: 470)
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
