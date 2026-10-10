import Foundation

/// Fixed storage, bounded work; all coefficient changes happen once per block.
final class InputPadDSP {
    private var filters = (0..<6).map { _ in BiquadFilter() }
    private var history = [Float](repeating: 0, count: 32768 * 2)
    private var cursor = 0
    private var phase: Float = 0
    private var lastMode: InputPadMode?
    private var lastState = IntellipanState(x: 99, y: 99)
    private var lastRate: Float = 0
    private var lastSmooth = false
    static func latencyFrames(mode: InputPadMode, smooth: Bool, rate: Float) -> Int {
        mode == .pitch ? Int(rate * (smooth ? 0.020 : 0.010)) + 2 : 0
    }
    func reset() {
        for i in filters.indices { filters[i].reset() }
        history.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        cursor = 0; phase = 0; lastMode = nil
    }
    private func read(_ delay: Float, _ channel: Int) -> Float {
        let position = Float(cursor) - delay
        let floorPosition = floorf(position)
        let index = Int(floorPosition) & 32767
        let fraction = position - floorPosition
        return history[index * 2 + channel] * (1-fraction) + history[((index+1) & 32767)*2+channel] * fraction
    }
    func process(buffer: UnsafeMutablePointer<Float>, frames: Int, rate: Float, mode: InputPadMode, state: IntellipanState, smooth: Bool) {
        let x = max(-1,min(1,state.x)), y = max(-1,min(1,state.y))
        if lastMode != mode || lastRate != rate || lastSmooth != smooth {
            reset(); lastMode = mode; lastRate = rate; lastSmooth = smooth; lastState = IntellipanState(x:99,y:99)
        }
        if lastState != state {
            lastState = state
            if mode == .intellipan {
                filters[0].setLowShelf(sampleRate:rate,cutoffHz:300,gainDB:-6*y)
                filters[1].setHighShelf(sampleRate:rate,cutoffHz:min(3000,rate*0.3),gainDB:6*y)
            } else if mode == .formant {
                // Experimental vowel coloration: suppress fixed resonances and emphasize shifted ones.
                // This deliberately does not claim vocal-envelope analysis or transparent resynthesis.
                let factor = powf(2,x), amount = min(1,abs(x)*4) * (0.65+0.35*(y+1)/2)
                for i in 0..<3 {
                    let base: Float = [500,1500,2500][i]
                    filters[i*2].setPeaking(sampleRate:rate,freqHz:min(rate*0.4,base),Q:2,gainDB:-9*amount)
                    filters[i*2+1].setPeaking(sampleRate:rate,freqHz:min(rate*0.4,base*factor),Q:2+max(0,y)*2,gainDB:9*amount)
                }
            }
        }
        if mode == .pan { return }
        if mode == .intellipan || mode == .formant {
            let count = mode == .intellipan ? 2 : 6
            for frame in 0..<frames {
                var l = buffer[frame*2], r = buffer[frame*2+1]
                for i in 0..<count { (l,r) = filters[i].process(left:l,right:r) }
                buffer[frame*2] = l; buffer[frame*2+1] = r
            }
            return
        }
        let window = Float(Self.latencyFrames(mode:.pitch,smooth:smooth,rate:rate)-2)*2
        let ratio = powf(2,x)
        let increment = mode == .pitch ? (1-ratio)/window : (0.1+2.4*(x+1))/rate
        let depth = abs(y), wet = depth*0.5
        for frame in 0..<frames {
            history[cursor*2] = buffer[frame*2]; history[cursor*2+1] = buffer[frame*2+1]
            if mode == .pitch {
                let second = phase < 0.5 ? phase+0.5 : phase-0.5
                let weight = 0.5-0.5*cosf(2*Float.pi*phase)
                for ch in 0..<2 {
                    let shifted = read(2+phase*window,ch)*weight + read(2+second*window,ch)*(1-weight)
                    let dry = read(window/2+2,ch)
                    let mix = 1-abs(y)*0.75
                    buffer[frame*2+ch] = shifted*mix + dry*(1-mix)
                }
            } else {
                for ch in 0..<2 {
                    let delay = rate * (0.012 + 0.005*depth*sinf(2*Float.pi*phase+Float(ch)*Float.pi/2))
                    buffer[frame*2+ch] = buffer[frame*2+ch]*(1-wet) + read(delay,ch)*wet
                }
            }
            phase += increment; phase -= floorf(phase)
            cursor = (cursor+1) & 32767
        }
    }
}
