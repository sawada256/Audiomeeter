import Foundation

@main struct PadSpectrumTests {
    static func main() {
        let n = 8192, bin = 171
        let tone = (0..<n*2).map { i in sinf(2*Float.pi*Float(bin)*Float(i/2)/Float(n)) * (i%2 == 0 ? 1 : -1) }
        let fft = SpectrumFFT(size:n)
        let powers = fft.powers(tone)
        precondition(abs(powers[bin]-1)<0.001, "Anti-phase stereo must retain power and unity-tone normalization")
        let pink = (0..<n/2).map { 1/Float(max(1,$0)) }
        let flat = SpectrumFFT.display(pink,rate:48000,size:n,slope:3.0103)
        let middle = Array(flat[80..<220])
        precondition(middle.max()! - middle.min()! < 0.6, "Pink power +3.01 dB/oct should be flat")
        let lowRate = SpectrumFFT.display(pink,rate:32000,size:n,slope:0)
        precondition(lowRate.last == -120, "Shared 20 Hz–20 kHz axis must not stretch frequencies below Nyquist")
        let mailbox = SpectrumFrameMailbox()
        let oldToken = mailbox.invalidate()
        for i in 0..<1000 { mailbox.publish([Float(i)],generation:oldToken) }
        precondition(mailbox.take() == [999] && mailbox.take() == nil, "Display backlog must collapse to newest frame")
        let token = mailbox.invalidate()
        mailbox.publish([1],generation:oldToken)
        precondition(mailbox.take() == nil, "Closed/reconfigured analyzer must reject stale work")
        mailbox.publish([2],generation:token)
        precondition(mailbox.take() == [2])
        var eq = MasterEQConfig()
        eq.bands[0].gainDB = 6; eq.bands[3].gainDB = -8
        for rate:Float in [44100,48000,96000] {
            let curve = ParametricEQ6Band.responseCurve(config:eq,sampleRate:rate)
            for i in curve.indices {
                let f = 20*powf(1000,Float(i)/200)
                precondition(abs(curve[i]-ParametricEQ6Band.combinedResponseDB(config:eq,freq:f,sampleRate:rate))<0.00001)
            }
        }
        let capture = SpectrumCapture()
        tone.withUnsafeBufferPointer { capture.write(bus:.A1,buffer:$0.baseAddress!,frames:n,sampleRate:48000) }
        precondition(capture.ring.availableRead()==0)
        capture.select(.A1)
        tone.withUnsafeBufferPointer { capture.write(bus:.B1,buffer:$0.baseAddress!,frames:n,sampleRate:48000) }
        precondition(capture.ring.availableRead()==0)
        tone.withUnsafeBufferPointer { capture.write(bus:.A1,buffer:$0.baseAddress!,frames:n,sampleRate:48000) }
        precondition(capture.ring.availableRead()==n && capture.sampleRate==48000)
        capture.select(nil)
        for mode in InputPadMode.allCases {
            for rate:Float in [44100,48000,192000] {
                let dsp = InputPadDSP()
                var block = [Float](repeating:0.1,count:1024)
                block.withUnsafeMutableBufferPointer { dsp.process(buffer:$0.baseAddress!,frames:512,rate:rate,mode:mode,state:IntellipanState(),smooth:false) }
                if [.pan,.intellipan,.formant,.modulation].contains(mode) { precondition(block.allSatisfy { abs($0-0.1)<0.00001 }, "Neutral PAD must be transparent") }
                for step in 0..<200 {
                    block = (0..<1024).map { sinf(Float($0+step*1024)*0.11)*0.2 }
                    block.withUnsafeMutableBufferPointer { dsp.process(buffer:$0.baseAddress!,frames:512,rate:rate,mode:mode,state:IntellipanState(x:step%2 == 0 ? -1:1,y:1),smooth:step%3 == 0) }
                    precondition(block.allSatisfy { $0.isFinite && abs($0)<10 })
                }
            }
        }
        for x:Float in [-1,1] {
            let dsp = InputPadDSP();var output=[Float]()
            for block in 0..<150 {
                var samples=(0..<1024).map { i in sinf(2*Float.pi*500*Float(block*512+i/2)/48000)*0.2 }
                samples.withUnsafeMutableBufferPointer { dsp.process(buffer:$0.baseAddress!,frames:512,rate:48000,mode:.pitch,state:IntellipanState(x:x),smooth:false) }
                if block>40 { output.append(contentsOf:stride(from:0,to:1024,by:2).map { samples[$0] }) }
            }
            let crossings=(1..<output.count).filter { output[$0-1]<=0 && output[$0]>0 }.count
            let frequency=Float(crossings)*48000/Float(output.count)
            precondition(abs(frequency-500*powf(2,x))<25,"Pitch ratio incorrect: \(frequency)")
        }
        precondition(InputPadDSP.latencyFrames(mode:.pitch,smooth:false,rate:48000)==482)
        print("PAD/spectrum passed: stereo FFT, pink slope, capture gating, neutral/extreme PAD stability, pitch octave ratios")
    }
}
