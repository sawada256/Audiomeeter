import SwiftUI
import AppKit

/// Vintage Console Vertical Fader with dB Graduation and Double-click 0dB Reset
public struct FaderSliderView: View {
    @Binding public var gainDB: Float
    public let height: CGFloat
    public let scrollStep: Double
    public let reverseTrackpadScroll: Bool
    public let reverseMouseScroll: Bool

    private let minDB: Float = -60.0
    private let maxDB: Float = 12.0
    private let zeroDBNorm: CGFloat = 0.833 // ~0dB location (60 / 72 = 0.833)

    public init(gainDB: Binding<Float>, height: CGFloat = 180, scrollStep: Double = 1, reverseTrackpadScroll: Bool = true, reverseMouseScroll: Bool = true) {
        self._gainDB = gainDB
        self.height = height
        self.scrollStep = scrollStep
        self.reverseTrackpadScroll = reverseTrackpadScroll
        self.reverseMouseScroll = reverseMouseScroll
    }

    private func dbToOffset(in totalHeight: CGFloat) -> CGFloat {
        let clamped = max(minDB, min(maxDB, gainDB))
        let norm = CGFloat((clamped - minDB) / (maxDB - minDB)) // 0.0 (bottom) to 1.0 (top)
        let usableHeight = totalHeight - 24 // account for knob height
        return (1.0 - norm) * usableHeight
    }

    private func offsetToDB(_ offset: CGFloat, in totalHeight: CGFloat) -> Float {
        let usableHeight = totalHeight - 24
        let clampedOffset = max(0, min(usableHeight, offset))
        let norm = 1.0 - Float(clampedOffset / usableHeight)
        let rawDB = minDB + norm * (maxDB - minDB)
        return round(rawDB * 10.0) / 10.0
    }

    public var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let knobY = dbToOffset(in: geo.size.height) + 12

                ZStack(alignment: .top) {
                    // Wide invisible hit area
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())

                    // Track Background Slot
                    RoundedRectangle(cornerRadius: 3)
                        .fill(VMTheme.faderTrack)
                        .frame(width: 8, height: geo.size.height)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.black, lineWidth: 1)
                        )
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    // 0 dB center reference tick
                    Rectangle()
                        .fill(VMTheme.textAccent.opacity(0.6))
                        .frame(width: 20, height: 1.5)
                        .position(x: geo.size.width / 2, y: (1.0 - zeroDBNorm) * (geo.size.height - 24) + 12)

                    // Fader Cap / Knob
                    ZStack {
                        // Knob Body
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [VMTheme.faderCapTop, VMTheme.faderCapBottom],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 36, height: 22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.7), radius: 3, y: 2)

                        // Center Neon Accent Line
                        Rectangle()
                            .fill(VMTheme.faderCyanLine)
                            .frame(width: 24, height: 2)
                            .shadow(color: VMTheme.faderCyanLine, radius: 2)
                    }
                    .position(x: geo.size.width / 2, y: knobY)
                }
                .contentShape(Rectangle())
                .overlay(VerticalFaderInteraction(gain: $gainDB, scrollStep: scrollStep, reverseTrackpad: reverseTrackpadScroll, reverseMouse: reverseMouseScroll))
            }
            .frame(width: 44, height: height)

            // dB Numeric readout badge
            Text(gainDB <= -59.5 ? "-inf dB" : String(format: "%+.1f dB", gainDB))
                .font(VMTheme.fontDigit)
                .foregroundColor(gainDB == 0.0 ? VMTheme.textAccent : (gainDB > 0 ? VMTheme.vuYellow : VMTheme.textPrimary))
                .frame(width: 58, height: 18)
                .background(Color.black.opacity(0.6))
                .cornerRadius(2)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(VMTheme.panelBorder.opacity(0.5), lineWidth: 1)
                )
                .onTapGesture(count: 2) {
                    self.gainDB = 0.0
                }
        }
    }
}

private struct VerticalFaderInteraction: NSViewRepresentable {
    @Binding var gain: Float
    let scrollStep: Double
    let reverseTrackpad: Bool
    let reverseMouse: Bool
    func makeNSView(context: Context) -> Track { Track() }
    func updateNSView(_ view: Track, context: Context) {
        view.gain = gain; view.step = scrollStep; view.changed = { gain = $0 }
        view.reverseTrackpad = reverseTrackpad; view.reverseMouse = reverseMouse
        view.setAccessibilityValue(NSNumber(value: gain))
    }
    final class Track: NSView {
        var gain: Float = 0, step: Double = 1
        var reverseTrackpad = true, reverseMouse = true
        var changed: ((Float) -> Void)?
        private var grabOffset: CGFloat = 0
        override var isFlipped: Bool { true }
        override init(frame: NSRect) {
            super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.slider)
            setAccessibilityLabel("フェーダー"); setAccessibilityMinValue(-60); setAccessibilityMaxValue(12)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        private var usableHeight: CGFloat { max(1, bounds.height - 24) }
        private func setGain(_ value: Float) { gain = min(12, max(-60, value)); changed?(gain) }
        private func move(_ event: NSEvent) {
            let y = convert(event.locationInWindow, from: nil).y - grabOffset - 12
            let value = -60 + 72 * (1 - Float(min(usableHeight, max(0, y)) / usableHeight))
            setGain(round(value * 10) / 10)
        }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount >= 2 { setGain(0); return }
            let y = convert(event.locationInWindow, from: nil).y
            let knobY = (1 - CGFloat((min(12, max(-60, gain)) + 60) / 72)) * usableHeight + 12
            // Treat the area 26 points above/below the cap's centre as a grab.
            // Preserve the grab offset so a rough click does not jump the gain.
            grabOffset = abs(y - knobY) <= 26 ? y - knobY : 0
            move(event)
        }
        override func mouseDragged(with event: NSEvent) { move(event) }
        override func scrollWheel(with event: NSEvent) {
            guard event.momentumPhase.isEmpty else { return }
            let delta = event.scrollingDeltaY
            guard delta != 0 else { super.scrollWheel(with: event); return }
            let ticks = event.hasPreciseScrollingDeltas ? Double(delta) / 10 : Double(delta)
            let direction: Double = (event.hasPreciseScrollingDeltas ? reverseTrackpad : reverseMouse) ? -1 : 1
            setGain(gain + Float(min(4, max(-4, ticks)) * step * direction))
        }
        override func accessibilityPerformIncrement() -> Bool { setGain(gain + Float(step)); return true }
        override func accessibilityPerformDecrement() -> Bool { setGain(gain - Float(step)); return true }
    }
}
