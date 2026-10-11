import SwiftUI
import AppKit
import QuartzCore

@MainActor final class SpectrumModel {
    let frames = SpectrumFrameMailbox()
    var latestPeak: Float = -100
    private let queue = DispatchQueue(label:"Audiomeeter.spectrum",qos:.utility)
    private var timer: DispatchSourceTimer?
    private var generation = 0
    func stop(_ capture: SpectrumCapture) {
        capture.select(nil); timer?.cancel(); timer = nil; generation += 1; frames.invalidate()
    }
    func start(capture: SpectrumCapture, bus: BusID, size: Int, window: SpectrumWindow, average: Float, slope: Float, smoothing: Float, fps: Int) {
        stop(capture)
        let token = generation
        let mailbox = frames
        let frameToken = mailbox.invalidate()
        let timer = DispatchSource.makeTimerSource(queue:queue)
        self.timer = timer
        // All mutable FFT/history state belongs exclusively to this serial queue.
        let fft = SpectrumFFT(size:size,window:window)
        var pending = [Float]()
        pending.reserveCapacity(size*4)
        var averaged = [Float](repeating:0,count:size/2)
        var started = false
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity:32768*2)
        timer.setCancelHandler { scratch.deallocate() }
        queue.async {
            _ = capture.ring.read(into:scratch,frameCount:32768)
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                capture.select(bus)
            }
        }
        var lastPublished = [Float]()
        timer.setEventHandler {
            let count = capture.ring.read(into:scratch,frameCount:32768)
            if count > 0 { pending.append(contentsOf:UnsafeBufferPointer(start:scratch,count:count*2)) }
            let rate = capture.sampleRate
            guard rate > 0 else { return }
            // Bound work: at most four FFT windows per UI tick. Drop visual history when behind.
            let hop = min(size, max(size/4, Int(rate / Float(fps) / 4)))
            if pending.count > (size+4*hop)*2 { pending.removeFirst(pending.count-(size+4*hop)*2) }
            var processed = false
            var steps = 0
            while pending.count >= size*2 && steps < 4 {
                let power = fft.powers(pending)
                let alpha: Float = average > 0 ? expf(-Float(hop)/rate/average) : 0
                for i in averaged.indices { averaged[i] = started ? alpha*averaged[i]+(1-alpha)*power[i] : power[i] }
                started = true; processed = true; steps += 1
                pending.removeFirst(hop*2)
            }
            guard processed else { return }
            let bins = SpectrumFFT.display(averaged,rate:rate,size:size,slope:slope,smoothing:smoothing)
            if bins != lastPublished {
                mailbox.publish(bins, generation: frameToken)
                lastPublished = bins
            }
        }
        timer.schedule(deadline:.now(),repeating:1.0/Double(fps),leeway:.milliseconds(fps >= 60 ? 2 : 8))
        timer.resume()
    }
}

struct SpectrumAnalyzerView<Content: View>: View {
    let content: (SpectrumModel, Bool) -> Content
    let capture: SpectrumCapture
    let bus: BusID
    // The control panel must not subscribe to FFT frames; only SpectrumPlot observes them.
    @State private var model = SpectrumModel()
    @AppStorage("spectrumTopDB") private var topDB = 0.0
    @AppStorage("spectrumRangeDB") private var rangeDB = 100.0
    @AppStorage("spectrumEnabled") private var enabled = false
    @AppStorage("spectrumFPS") private var fps = 20
    @AppStorage("spectrumSize") private var size = 8192
    @AppStorage("spectrumWindow") private var window = "Hann"
    @AppStorage("spectrumAverage") private var average = 0.3
    @AppStorage("spectrumSlope") private var slope = 3.0103
    @AppStorage("spectrumSmoothing") private var smoothing = 1.0/6
    private var signature: String { "\(fps)-\(enabled)-\(size)-\(window)-\(average)-\(slope)-\(smoothing)" }
    private func refresh() {
        guard enabled else { model.stop(capture); return }
        model.start(capture:capture,bus:bus,size:size,window:SpectrumWindow(rawValue:window) ?? .hann,
                    average:Float(average),slope:Float(slope),smoothing:Float(smoothing), fps:[20,30,60].contains(fps) ? fps : 20)
    }
    var body: some View {
        VStack(spacing:4) {
            HStack {
                Toggle("SPECTRUM",isOn:$enabled).toggleStyle(.switch)
                if enabled {
                    Menu("Response") {
                        Button("Fast • 2048 / 30 ms / 60 fps") { size = 2048; average = 0.03; fps = 60 }
                        Button("Balanced • 8192 / 300 ms / 20 fps") { size = 8192; average = 0.3; fps = 20 }
                        Button("Detailed • 16384 / 600 ms / 20 fps") { size = 16384; average = 0.6; fps = 20 }
                    }.frame(width:100)
                    Picker("FPS",selection:$fps) { ForEach([20,30,60],id:\.self) { Text("\($0)").tag($0) } }.frame(width:90)
                    Picker("FFT",selection:$size) { ForEach([2048,4096,8192,16384],id:\.self) { Text("\($0)").tag($0) } }.frame(width:120)
                    Picker("Window",selection:$window) { ForEach(SpectrumWindow.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }.frame(width:155)
                }
                Spacer(minLength:0)
            }.font(.caption).controlSize(.mini)
            if enabled {
                HStack {
                    Picker("Top", selection:$topDB) { ForEach([-60.0,-48,-36,-24,-12,0,12,24],id:\.self) { Text("\(Int($0)) dB").tag($0) } }.frame(width:110)
                    Picker("Range", selection:$rangeDB) { ForEach([40.0,60,80,100,120],id:\.self) { Text("\(Int($0)) dB").tag($0) } }.frame(width:115)
                    Button("Auto") { topDB = min(24,max(-60,ceil((Double(model.latestPeak)+6)/12)*12)) }
                    Spacer(minLength:0)
                }.font(.caption).controlSize(.mini)
                HStack {
                    Picker("Avg",selection:$average) { ForEach([0.0,0.03,0.05,0.1,0.3,0.6,1.0],id:\.self) { Text("\(Int($0*1000)) ms").tag($0) } }.frame(width:120)
                    Picker("Slope",selection:$slope) { ForEach([0.0,3.0103,4.5,6.0],id:\.self) { Text(String(format:"%.2f dB/oct",$0)).tag($0) } }.frame(width:155)
                    Picker("Smooth",selection:$smoothing) { Text("1/12 oct").tag(1.0/12);Text("1/6 oct").tag(1.0/6);Text("1/3 oct").tag(1.0/3) }.frame(width:135)
                Spacer(minLength:0)
                }.font(.caption).controlSize(.mini)
            }
        }.padding(.horizontal,12).padding(.vertical,4)
            .onAppear(perform:refresh).onChange(of:signature) { _, _ in refresh() }.onDisappear { model.stop(capture) }
        content(model, enabled)
    }
}
/// Native layer updates avoid invalidating the SwiftUI EQ/control tree for every FFT frame.
struct SpectrumPlot: NSViewRepresentable {
    let model: SpectrumModel
    @AppStorage("spectrumTopDB") private var topDB = 0.0
    @AppStorage("spectrumRangeDB") private var rangeDB = 100.0
    func makeNSView(context: Context) -> SpectrumLayerView { SpectrumLayerView(frames: model.frames) }
    func updateNSView(_ view: SpectrumLayerView, context: Context) { view.frames = model.frames; view.model = model; view.topDB = topDB; view.rangeDB = rangeDB; view.needsLayout = true }
    static func dismantleNSView(_ view: SpectrumLayerView, coordinator: ()) { view.stop() }
}
final class SpectrumLayerView: NSView {
    var frames: SpectrumFrameMailbox
    weak var model: SpectrumModel?
    var topDB = 0.0
    var rangeDB = 100.0
    private let curve = CAShapeLayer()
    private var timer: Timer?
    private var bins = [Float]()
    private var lastUpdate: CFTimeInterval = 0
    init(frames: SpectrumFrameMailbox) {
        self.frames = frames
        super.init(frame: .zero)
        wantsLayer = true
        curve.strokeColor = NSColor.systemGreen.withAlphaComponent(0.75).cgColor
        curve.fillColor = nil; curve.lineWidth = 1
        layer?.addSublayer(curve)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        let timer = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in self?.displayNewestFrame() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func path() -> CGPath {
        let result = CGMutablePath()
        for i in bins.indices {
            let point = CGPoint(x: bounds.width * CGFloat(i) / CGFloat(max(1,bins.count-1)),
                                y: bounds.height * (1-CGFloat(min(rangeDB,max(0,topDB-Double(bins[i]))))/rangeDB))
            if i == 0 { result.move(to: point) } else { result.addLine(to: point) }
        }
        return result
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        curve.frame = bounds; curve.path = path()
        CATransaction.commit()
    }
    private func displayNewestFrame() {
        guard window?.occlusionState.contains(.visible) == true, let newest = frames.take() else { return }
        bins = newest
        model?.latestPeak = bins.max() ?? -100
        let now = CACurrentMediaTime()
        let from = curve.presentation()?.path ?? curve.path
        let next = path()
        CATransaction.begin(); CATransaction.setDisableActions(true); curve.path = next; CATransaction.commit()
        if let from, !from.isEmpty {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = from; animation.toValue = next
            animation.duration = now-lastUpdate > 0.25 ? 1.0/60 : min(0.10,max(1.0/60,now-lastUpdate))
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            curve.add(animation, forKey: "spectrum")
        }
        lastUpdate = now
    }
}
struct SpectrumAxis: View {
    @AppStorage("spectrumTopDB") private var topDB = 0.0
    @AppStorage("spectrumRangeDB") private var rangeDB = 100.0
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<4,id:\.self) { tick in
                let db = Int(topDB-rangeDB*Double(tick)/3)
                Text("\(db)").font(.system(size:9,design:.monospaced)).foregroundStyle(.green.opacity(0.8))
                    .position(x:22,y:max(10,min(geo.size.height-22,geo.size.height*CGFloat(tick)/3)))
            }
            Text("dB*").font(.system(size:8)).foregroundStyle(.green.opacity(0.8)).position(x:22,y:geo.size.height-8)
        }.frame(width:44).help(L10n.text("スペクトラムの表示値（Slope補正後）。EQゲインとは別の軸です。"))
    }
}
