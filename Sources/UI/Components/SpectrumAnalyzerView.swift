import SwiftUI

@MainActor final class SpectrumModel: ObservableObject {
    @Published var bins = [Float](repeating:-120,count:256)
    private let queue = DispatchQueue(label:"Audiomeeter.spectrum",qos:.utility)
    private var timer: DispatchSourceTimer?
    private var generation = 0
    func stop(_ capture: SpectrumCapture) {
        capture.select(nil); timer?.cancel(); timer = nil; generation += 1
    }
    func start(capture: SpectrumCapture, bus: BusID, size: Int, window: SpectrumWindow, average: Float, slope: Float, smoothing: Float, fps: Int) {
        stop(capture)
        let token = generation
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
        timer.setEventHandler { [weak self] in
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
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.bins = bins
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
struct SpectrumPlot: View {
    @ObservedObject var model: SpectrumModel
    var body: some View {
        Canvas(rendersAsynchronously: true) { context,size in
            var curve = Path()
            for i in model.bins.indices {
                let p = CGPoint(x:size.width*CGFloat(i)/255,y:size.height*CGFloat(min(100,max(0,-model.bins[i])))/100)
                if i == 0 { curve.move(to:p) } else { curve.addLine(to:p) }
            }
            context.stroke(curve,with:.color(.green.opacity(0.75)),lineWidth:1)
        }
    }
}
struct SpectrumAxis: View {
    var body: some View {
        GeometryReader { geo in
            ForEach([-90,-60,-30,0],id:\.self) { db in
                Text("\(db)").font(.system(size:9,design:.monospaced)).foregroundStyle(.green.opacity(0.8))
                    .position(x:22,y:max(10,geo.size.height*CGFloat(-db)/100))
            }
            Text("dB*").font(.system(size:8)).foregroundStyle(.green.opacity(0.8)).position(x:22,y:geo.size.height-8)
        }.frame(width:44).help(L10n.text("スペクトラムの表示値（Slope補正後）。EQゲインとは別の軸です。"))
    }
}
