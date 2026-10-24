import SwiftUI
import AppKit

struct InputPadView: View {
    @ObservedObject var appState: AppState
    let strip: StripID
    private var settings: StripSettings { appState.strips[strip] ?? StripSettings() }
    private var mode: InputPadMode { settings.padMode ?? .colorPan }
    private var state: PadState {
        switch mode {
        case .colorPan: return settings.colorPad
        case .pan: return PadState(x:settings.pan ?? 0,y:0)
        case .modulation: return settings.padModulation ?? PadState()
        case .pitch: return settings.padPitch ?? PadState()
        case .formant: return settings.padFormant ?? PadState()
        }
    }
    var body: some View {
        VStack(spacing:2) {
            Menu {
                ForEach(InputPadMode.allCases,id:\.rawValue) { item in
                    Button(item.rawValue) { appState.setInputPad(strip:strip,mode:item) }
                }
                Divider()
                Button("PITCH: Low Latency (~10 ms)") { appState.setInputPad(strip:strip,smooth:false) }
                Button("PITCH: Smooth (~20 ms)") { appState.setInputPad(strip:strip,smooth:true) }
            } label: { Text(mode.rawValue).font(.system(size:9,weight:.bold)).frame(maxWidth:.infinity) }
            .menuStyle(.borderlessButton)
            PadSurface(mode:mode,state:state,changed: { appState.setInputPad(strip:strip,state:$0) },next: {
                let modes = InputPadMode.allCases
                let index = modes.firstIndex(of:mode) ?? 0
                appState.setInputPad(strip:strip,mode:modes[(index+1)%modes.count])
            }).frame(height:86)
        }.frame(maxWidth:.infinity).frame(height:106)
        .help(L10n.text("右クリックでPAD切替、ダブルクリックで中央。FORMANTは共鳴帯域を動かす試験用音色処理です。"))
    }
}
private struct PadSurface: NSViewRepresentable {
    let mode: InputPadMode
    let state: PadState
    let changed: (PadState)->Void
    let next: ()->Void
    func makeNSView(context:Context)->Surface { Surface() }
    func updateNSView(_ view:Surface,context:Context) {
        view.mode=mode;view.state=state;view.changed=changed;view.next=next;view.needsDisplay=true
        view.setAccessibilityLabel(mode.rawValue);view.setAccessibilityValue("\(state.x), \(state.y)")
    }
    final class Surface: NSView {
        var mode=InputPadMode.colorPan, state=PadState()
        var changed: ((PadState)->Void)?, next:(()->Void)?
        override var acceptsFirstResponder:Bool { true }
        override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }
        override func mouseDown(with event:NSEvent) {
            window?.makeKey();window?.makeFirstResponder(self)
            if event.clickCount==2 { changed?(PadState());return }
            move(event)
        }
        override func mouseDragged(with event:NSEvent) { move(event) }
        override func rightMouseDown(with event:NSEvent) { next?() }
        private func move(_ event:NSEvent) {
            let p=convert(event.locationInWindow,from:nil)
            var x=Float((p.x-8)/max(1,bounds.width-16)*2-1)
            var y=Float((p.y-12)/max(1,bounds.height-24)*2-1)
            if abs(x)<0.045 { x=0 };if abs(y)<0.045 { y=0 }
            changed?(PadState(x:max(-1,min(1,x)),y:mode == .pan ? 0 : max(-1,min(1,y))))
        }
        override func draw(_ dirtyRect:NSRect) {
            NSColor(white:0.07,alpha:1).setFill();bounds.fill()
            let grid=NSBezierPath();grid.move(to:NSPoint(x:8,y:bounds.midY));grid.line(to:NSPoint(x:bounds.width-8,y:bounds.midY))
            if mode != .pan { grid.move(to:NSPoint(x:bounds.midX,y:12));grid.line(to:NSPoint(x:bounds.midX,y:bounds.height-12)) }
            NSColor.darkGray.setStroke();grid.lineWidth=1;grid.stroke()
            let p=NSPoint(x:8+CGFloat(state.x+1)/2*(bounds.width-16),y:12+CGFloat(state.y+1)/2*(bounds.height-24))
            NSColor.systemCyan.setFill();NSBezierPath(ovalIn:NSRect(x:p.x-4,y:p.y-4,width:8,height:8)).fill()
            let labels: (String,String,String)
            switch mode {
            case .pan: labels=("L","R",abs(state.x)<0.005 ? "C" : String(format:"%@ %.0f",state.x<0 ? "L":"R",abs(state.x)*100))
            case .colorPan: labels=("L","R","BRIGHT ↑ • DARK ↓")
            case .modulation: labels=("SLOW","FAST","DEPTH ↑")
            case .pitch: labels=("−12 st","+12 st",String(format:"%+.1f st • %.0f%%",state.x*12,(1-abs(state.y)*0.75)*100))
            case .formant: labels=("LOW","HIGH","RESONANCE ↑ • EXP")
            }
            let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:8),.foregroundColor:NSColor.lightGray]
            (labels.0 as NSString).draw(at:NSPoint(x:4,y:2),withAttributes:attrs)
            let right=labels.1 as NSString;right.draw(at:NSPoint(x:bounds.width-right.size(withAttributes:attrs).width-4,y:2),withAttributes:attrs)
            let top=labels.2 as NSString;top.draw(at:NSPoint(x:(bounds.width-top.size(withAttributes:attrs).width)/2,y:bounds.height-11),withAttributes:attrs)
        }
    }
}
