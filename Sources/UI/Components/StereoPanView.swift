import SwiftUI
import AppKit

struct StereoPanView: View {
    @ObservedObject var appState: AppState
    let strip: StripID
    private var value: Float { appState.strips[strip]?.pan ?? 0 }
    var body: some View {
        HStack(spacing: 4) {
            Text(L10n.text("PAN")).font(VMTheme.fontSmall)
            PanTrack(value: value) { appState.setStripPan(strip: strip, pan: $0) }
            Text(StereoPanControl.label(value)).font(VMTheme.fontSmall).frame(width: 28)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { appState.setStripPan(strip: strip, pan: 0) }
        }.frame(height: 18).padding(.horizontal, 4)
        .help(L10n.text("左右のバランス。中央付近でスナップ、ダブルクリックで中央"))
    }
}

private struct PanTrack: NSViewRepresentable {
    let value: Float
    let changed: (Float) -> Void
    func makeNSView(context: Context) -> PanTrackNSView { PanTrackNSView() }
    func updateNSView(_ view: PanTrackNSView, context: Context) {
        view.value = value; view.changed = changed; view.needsDisplay = true
        view.setAccessibilityValue(NSNumber(value: value))
        view.setAccessibilityValueDescription(StereoPanControl.label(value))
    }
}
private final class PanTrackNSView: NSView {
    var value: Float = 0
    var changed: ((Float) -> Void)?
    private var resetting = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.slider); setAccessibilityLabel(L10n.text("PAN"))
        setAccessibilityMinValue(NSNumber(value: -1)); setAccessibilityMaxValue(NSNumber(value: 1))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        resetting = event.clickCount >= 2
        if resetting { changed?(0) } else { move(event) }
    }
    override func mouseDragged(with event: NSEvent) { if !resetting { move(event) } }
    override func mouseUp(with event: NSEvent) { resetting = false }
    private func move(_ event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let fraction = (x - 6) / max(1, bounds.width - 12)
        changed?(StereoPanControl.normalized(Float(fraction * 2 - 1)))
    }
    override func accessibilityPerformIncrement() -> Bool { changed?(StereoPanControl.normalized(value + 0.1)); return true }
    override func accessibilityPerformDecrement() -> Bool { changed?(StereoPanControl.normalized(value - 0.1)); return true }
    override func draw(_ dirtyRect: NSRect) {
        let middle = bounds.midX, y = bounds.midY
        let x = 6 + CGFloat(min(1,max(-1,value)) + 1) * max(1,bounds.width - 12) / 2
        NSColor(white: 0.24, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x:6,y:y-2,width:max(1,bounds.width-12),height:4),xRadius:2,yRadius:2).fill()
        NSColor.systemTeal.setFill()
        NSBezierPath(roundedRect: NSRect(x:min(middle,x),y:y-2,width:abs(x-middle),height:4),xRadius:2,yRadius:2).fill()
        NSColor(white:0.62,alpha:1).setFill()
        NSRect(x:middle-0.5,y:y-5,width:1,height:10).fill()
        NSColor(white:0.87,alpha:1).setFill()
        NSBezierPath(ovalIn:NSRect(x:x-5,y:y-5,width:10,height:10)).fill()
    }
}
