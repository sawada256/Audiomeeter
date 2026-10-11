import Foundation
import Accelerate
import VMNative

/// Audio callback only copies to a bounded SPSC ring while a visible analyzer is enabled.
final class SpectrumCapture {
    let ring = StereoRingBuffer(capacityFrames: 32768)
    private let selected = vm_counter_create()!
    private let rate = vm_counter_create()!
    deinit { vm_counter_destroy(selected); vm_counter_destroy(rate) }
    func select(_ bus: BusID?) { vm_counter_store(selected, bus.map { UInt64($0.rawValue + 1) } ?? 0) }
    var sampleRate: Float { Float(vm_counter_load(rate)) }
    func write(bus: BusID, buffer: UnsafePointer<Float>, frames: Int, sampleRate: Float) {
        guard vm_counter_load(selected) == UInt64(bus.rawValue + 1) else { return }
        vm_counter_store(rate, UInt64(sampleRate))
        ring.write(from: buffer, frameCount: frames)
    }
}

enum SpectrumWindow: String, CaseIterable { case hann = "Hann", blackman = "Blackman", rectangular = "Rectangular" }

/// Runs on the analysis queue, never on the render callback.
final class SpectrumFFT {
    let size: Int
    private let setup: FFTSetup
    private let logSize: vDSP_Length
    private var window: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private let scale: Float
    init(size: Int = 8192, window type: SpectrumWindow = .hann) {
        self.size = [2048,4096,8192,16384].contains(size) ? size : 8192
        logSize = vDSP_Length(log2(Double(self.size)))
        setup = vDSP_create_fftsetup(logSize, FFTRadix(kFFTRadix2))!
        let count = self.size
        window = (0..<count).map { i in
            let phase = 2 * Float.pi * Float(i) / Float(count)
            switch type {
            case .hann: return 0.5 - 0.5 * cosf(phase)
            case .blackman: return 0.42 - 0.5 * cosf(phase) + 0.08 * cosf(2 * phase)
            case .rectangular: return 1
            }
        }
        scale = 2 / window.reduce(0,+)
        real = [Float](repeating:0,count:self.size); imaginary = real
    }
    deinit { vDSP_destroy_fftsetup(setup) }
    func powers(_ stereo: [Float]) -> [Float] {
        precondition(stereo.count >= size * 2)
        var result = [Float](repeating:0,count:size / 2)
        for channel in 0..<2 {
            for i in 0..<size { real[i] = stereo[i*2+channel] * window[i]; imaginary[i] = 0 }
            real.withUnsafeMutableBufferPointer { r in
                imaginary.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp:r.baseAddress!,imagp:im.baseAddress!)
                    vDSP_fft_zip(setup,&split,1,logSize,FFTDirection(FFT_FORWARD))
                }
            }
            for i in result.indices { result[i] += (real[i]*real[i]+imaginary[i]*imaginary[i])*scale*scale*0.5 }
        }
        return result
    }
    static func display(_ powers: [Float], rate: Float, size: Int, slope: Float, smoothing: Float = 1.0/6) -> [Float] {
        guard rate > 0 else { return [Float](repeating:-120,count:256) }
        return (0..<256).map { i in
            let frequency = 20 * powf(20000.0/20,Float(i)/255)
            let halfWidth = max(1.0/48,smoothing)/2
            let low = max(1,Int(frequency*powf(2,-halfWidth)*Float(size)/rate))
            let high = min(powers.count-1,max(low,Int(frequency*powf(2,halfWidth)*Float(size)/rate)))
            guard low <= high else { return -120 }
            var sum: Float = 0
            for bin in low...high { sum += powers[bin] }
            return max(-120,10*log10f(max(1e-12,sum/Float(high-low+1))) + slope*log2f(frequency/1000))
        }
    }
}

/// Single-slot display mailbox. Never touched by the real-time audio callback.
/// Slow UI consumers receive only the newest frame; obsolete sessions cannot publish.
final class SpectrumFrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var frame: [Float]?
    @discardableResult func invalidate() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1; frame = nil; return generation
    }
    func publish(_ values: [Float], generation token: Int) {
        lock.lock(); defer { lock.unlock() }
        if token == generation { frame = values }
    }
    func take() -> [Float]? {
        lock.lock(); defer { lock.unlock() }
        let result = frame; frame = nil; return result
    }
}
