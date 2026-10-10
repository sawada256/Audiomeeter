import SwiftUI
import AppKit
import Combine

struct MiniMixerView: View {
    @ObservedObject private var localization = LocalizationStore.shared
    @ObservedObject var state: AppState
    private var preferences: DesktopControlsPreferences { state.desktopControls }
    private var trimStrips: [StripID] {
        guard preferences.showAppTrims else { return [] }
        switch preferences.appTrimSource {
        case .automatic: return state.systemOutputStrip.map { [$0] } ?? []
        case .vaio: return [.virtualVAIO]
        case .aux: return [.virtualAUX]
        case .both: return [.virtualVAIO, .virtualAUX]
        }
    }
    private func gain(_ target: InsertTarget) -> Binding<Double> {
        Binding(get: {
            switch target { case .bus(let b): return Double(state.buses[b]?.gainDB ?? 0); case .strip(let s): return Double(state.strips[s]?.gainDB ?? 0) }
        }, set: {
            switch target { case .bus(let b): state.setBusGain(bus: b, gainDB: Float($0)); case .strip(let s): state.setStripGain(strip: s, gainDB: Float($0)) }
        })
    }
    private func isMuted(_ target: InsertTarget) -> Bool {
        switch target { case .bus(let b): return state.buses[b]?.isMuted ?? false; case .strip(let s): return state.strips[s]?.isMuted ?? false }
    }
    private func appGain(strip: StripID, item: AppVolumeItem) -> Binding<Double> {
        Binding<Double>(get: {
            let items: [AppVolumeItem] = strip == .virtualVAIO ? state.vaioAppVolumes : state.auxAppVolumes
            let found: AppVolumeItem? = items.first(where: { $0.pid == item.pid })
            let value: Float = found?.volume ?? item.volume
            return Double(value)
        }, set: { state.setAppTrim(strip: strip, pid: item.pid, gain: Float($0)) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(L10n.text("MINI MIXER")).font(.system(size: 9, weight: .bold)); Spacer(); Text("dB").font(.system(size: 9)).foregroundStyle(.secondary) }
            ForEach(InsertTarget.all) { target in
                let options = preferences.overlayChannels[target.id] ?? MiniMixerChannel()
                let muted = isMuted(target)
                if options.fader || options.meter {
                    HStack(spacing: 7) {
                        HStack(spacing: 2) {
                            Text(target.name).font(.system(size: 10, weight: .semibold))
                                .frame(width: 26, alignment: .leading)
                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 9)).foregroundStyle(.orange)
                                .frame(width: 14)
                                .opacity(muted ? 1 : 0)
                                .accessibilityLabel(L10n.text("{0} ミュート中", [String(describing: target.name)]))
                                .accessibilityHidden(!muted)
                        }.frame(width: 42, alignment: .leading)
                        if options.fader {
                            MiniGainSlider(value: gain(target), range: -60...12, neutral: 0, scrollStep: preferences.gainStep, reverseTrackpad: preferences.reverseTrackpadScroll ?? true, reverseMouse: preferences.reverseMouseScroll ?? true, label: L10n.text("{0} フェーダー", [String(describing: target.name)]), muted: muted).frame(height: 28)
                            Text(String(format: "%+.1f", gain(target).wrappedValue)).font(.system(size: 9, design: .monospaced)).frame(width: 38)
                        }
                        if options.meter { LiveCompactStereoMeter(meters: state.meterStore, target: target).frame(width: options.fader ? 58 : 222, height: 12).accessibilityLabel(L10n.text("{0} レベルメーター", [String(describing: target.name)])) }
                    }.frame(height: 28)
                }
            }
            if preferences.showAppTrims {
                Divider()
                if trimStrips.isEmpty { Text(L10n.text("OSの出力先がVAIO／AUXではありません")).font(.caption2).foregroundStyle(.secondary) }
                ForEach(trimStrips) { strip in
                    Text("\(strip.shortName) • APPS").font(.system(size: 9, weight: .bold))
                    if state.appTrimSupported[strip] != true {
                        Text(state.appTrimErrors[strip] ?? L10n.text("アプリ別トリムを取得中…")).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        let items = strip == .virtualVAIO ? state.vaioAppVolumes : state.auxAppVolumes
                        if items.isEmpty { Text(L10n.text("出力中のアプリなし")).font(.caption2).foregroundStyle(.secondary) }
                        if !items.isEmpty { ScrollView {
                        ForEach(items) { item in
                            HStack(spacing: 6) {
                                Text(item.name).font(.system(size: 10)).lineLimit(1).frame(width: 100, alignment: .leading)
                                MiniGainSlider(value: appGain(strip: strip, item: item), range: 0...2, neutral: 1, scrollStep: 0.05, reverseTrackpad: preferences.reverseTrackpadScroll ?? true, reverseMouse: preferences.reverseMouseScroll ?? true, label: L10n.text("{0} トリム", [String(describing: item.name)])).frame(height: 28)
                                Text("\(Int(item.volume * 100))%").font(.system(size: 9, design: .monospaced)).frame(width: 35)
                            }.frame(height: 28)
                        }
                        }.frame(height: min(168, CGFloat(items.count * 36))) }
                    }
                }
            }
            if !preferences.overlayChannels.values.contains(where: { $0.fader || $0.meter }) && !preferences.showAppTrims {
                Text(L10n.text("設定で表示するフェーダー／メーターを選択")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .id(localization.language)
        .padding(12).frame(width: 330)
        .foregroundStyle(.white)
        .background(Color(red: 0.10, green: 0.12, blue: 0.14), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15)))
        .preferredColorScheme(.dark)
    }
}

/// A held Control shortcut turns a primary mouse click into a secondary click.
/// Both buttons therefore adjust this compact slider, without activating the mixer.
private struct MiniGainSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let neutral: Double
    let scrollStep: Double
    var reverseTrackpad = true
    var reverseMouse = true
    let label: String
    var muted = false
    func makeNSView(context: Context) -> Track { Track() }
    func updateNSView(_ view: Track, context: Context) {
        view.value = value; view.range = range; view.neutral = neutral; view.scrollStep = scrollStep; view.changed = { value = $0 }; view.needsDisplay = true
        view.reverseTrackpad = reverseTrackpad; view.reverseMouse = reverseMouse; view.muted = muted
        view.setAccessibilityHelp(muted ? L10n.text("ミュート中。フェーダーは調整できます") : "")
        view.setAccessibilityLabel(label); view.setAccessibilityValue(NSNumber(value: value))
        view.setAccessibilityMinValue(NSNumber(value: range.lowerBound)); view.setAccessibilityMaxValue(NSNumber(value: range.upperBound))
    }
    final class Track: NSView {
        var value: Double = 0, neutral: Double = 0
        var range: ClosedRange<Double> = -60...12
        var scrollStep: Double = 1
        var reverseTrackpad = true, reverseMouse = true
        var muted = false
        var changed: ((Double) -> Void)?
        override init(frame: NSRect) { super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.slider) }
        required init?(coder: NSCoder) { fatalError() }
        override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 28) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        private func move(_ event: NSEvent) {
            let x = convert(event.locationInWindow, from: nil).x
            let fraction = min(1, max(0, Double((x - 5) / max(1, bounds.width - 10))))
            changed?(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
        }
        override func mouseDown(with event: NSEvent) { event.clickCount >= 2 ? changed?(neutral) : move(event) }
        override func rightMouseDown(with event: NSEvent) { move(event) }
        override func mouseDragged(with event: NSEvent) { move(event) }
        override func rightMouseDragged(with event: NSEvent) { move(event) }
        override func scrollWheel(with event: NSEvent) {
            // Momentum should not keep changing gain after the fingers leave the trackpad.
            guard event.momentumPhase.isEmpty else { return }
            let delta = event.scrollingDeltaY
            guard delta != 0 else { super.scrollWheel(with: event); return }
            let ticks = event.hasPreciseScrollingDeltas ? Double(delta) / 10 : Double(delta)
            let direction: Double = (event.hasPreciseScrollingDeltas ? reverseTrackpad : reverseMouse) ? -1 : 1
            value = min(range.upperBound, max(range.lowerBound, value + min(4, max(-4, ticks)) * scrollStep * direction))
            changed?(value); needsDisplay = true
        }
        override func accessibilityPerformIncrement() -> Bool { changed?(min(range.upperBound, value + (range.upperBound == 2 ? 0.1 : 1))); return true }
        override func accessibilityPerformDecrement() -> Bool { changed?(max(range.lowerBound, value - (range.upperBound == 2 ? 0.1 : 1))); return true }
        override func draw(_ dirtyRect: NSRect) {
            let y = bounds.midY, fraction = min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
            let width = max(1, bounds.width - 10), x = 5 + width * fraction
            NSColor(white: 0.25, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: 5, y: y-2, width: width, height: 4), xRadius: 2, yRadius: 2).fill()
            (muted ? NSColor.systemGray : NSColor.systemTeal).setFill(); NSBezierPath(roundedRect: NSRect(x: 5, y: y-2, width: width * fraction, height: 4), xRadius: 2, yRadius: 2).fill()
            (muted ? NSColor.lightGray : NSColor.white).setFill(); NSBezierPath(ovalIn: NSRect(x: x-4, y: y-4, width: 8, height: 8)).fill()
        }
    }
}

private struct LiveCompactStereoMeter: View {
    @ObservedObject var meters: MixerMeterStore
    let target: InsertTarget
    var body: some View { CompactStereoMeter(level: meters.level(target)) }
}

struct CompactStereoMeter: View {
    let level: MeterLevel
    private func fraction(_ db: Float) -> CGFloat { CGFloat(min(1, max(0, (db + 60) / 66))) }
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 2) {
                ForEach([level.leftRMSDB, level.rightRMSDB].indices, id: \.self) { channel in
                    let rms = channel == 0 ? level.leftRMSDB : level.rightRMSDB
                    let peak = channel == 0 ? level.leftPeakDB : level.rightPeakDB
                    ZStack(alignment: .leading) {
                        Color.white.opacity(0.12)
                        LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing).frame(width: geo.size.width * fraction(rms))
                        Color.white.frame(width: 1).offset(x: max(0, geo.size.width * fraction(peak) - 1))
                    }.frame(height: 5).clipped()
                }
            }
        }
    }
}

final class MiniMixerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private final class MiniMixerHostingView: NSHostingView<MiniMixerView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class DesktopControlsCoordinator {
    static weak var current: DesktopControlsCoordinator?
    private let state: AppState
    let hotkeys: MixerHotkeys
    private let volumeGuard = VirtualOutputVolumeGuard()
    private let panel: MiniMixerPanel
    private let hosting: MiniMixerHostingView
    private var subscriptions: Set<AnyCancellable> = []
    private var held = false
    private var hotkeyVisible = false
    private var hotkeyHideTimer: Timer?
    init(state: AppState) {
        self.state = state; hotkeys = MixerHotkeys(state: state)
        hosting = MiniMixerHostingView(rootView: MiniMixerView(state: state))
        panel = MiniMixerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = hosting; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
        panel.title = "Audiomeeter Mini Mixer"; panel.canHide = false; panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        Self.current = self
        hotkeys.overlayHeld = { [weak self] down in guard let self, self.held != down else { return }; self.held = down; self.updatePanel() }
        hotkeys.volumeHotkeyPerformed = { [weak self] in self?.showForVolumeHotkey() }
        state.$desktopControls.dropFirst().sink { [weak self] _ in
            // @Published emits before assignment; apply on the next main-run-loop turn.
            DispatchQueue.main.async { self?.configure() }
        }.store(in: &subscriptions)
        state.$outputDevices.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.updateVolumeGuard() } }.store(in: &subscriptions)
        Publishers.Merge3(state.$vaioAppVolumes.map { _ in () }, state.$auxAppVolumes.map { _ in () }, state.$systemOutputStrip.map { _ in () })
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main).sink { [weak self] _ in self?.updatePanel() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in self?.updatePanel() }.store(in: &subscriptions)
        configure()
    }
    private func showForVolumeHotkey() {
        hotkeyHideTimer?.invalidate()
        hotkeyVisible = true
        updatePanel()
        let timer = Timer(timeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hotkeyVisible = false
                self.hotkeyHideTimer = nil
                self.updatePanel()
            }
        }
        hotkeyHideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func updateVolumeGuard() { volumeGuard.configure(enabled: state.desktopControls.keepVirtualVolumeAtMaximum, devices: state.outputDevices) }
    private func configure() { hotkeys.configure(); updateVolumeGuard(); updatePanel() }
    private func updatePanel() {
        let p = state.desktopControls
        guard hotkeyVisible || p.overlayMode == .always || (p.overlayMode == .held && held) else { panel.orderOut(nil); return }
        panel.alphaValue = p.overlayOpacity
        hosting.invalidateIntrinsicContentSize(); hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let bounds = screen.visibleFrame
        let right = p.overlayCorner == .topRight || p.overlayCorner == .bottomRight
        let top = p.overlayCorner == .topRight || p.overlayCorner == .topLeft
        let width = min(size.width, bounds.width - 20), height = min(size.height, bounds.height - 20)
        panel.setFrame(NSRect(x: right ? bounds.maxX - width - 12 : bounds.minX + 12, y: top ? bounds.maxY - height - 12 : bounds.minY + 12, width: width, height: height), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    func stop() { hotkeyHideTimer?.invalidate(); hotkeyHideTimer = nil; hotkeyVisible = false; hotkeys.volumeHotkeyPerformed = nil; subscriptions.removeAll(); hotkeys.stop(); volumeGuard.stop(); panel.orderOut(nil); Self.current = nil }
}
