import Foundation

@main struct BusProcessingTests {
    static func main() throws {
        precondition(BusProcessingStage.standard == [.preInserts, .fader, .postInserts, .eq, .limiter])
        precondition(!BusProcessingStage.isValid([.eq, .postInserts, .fader, .preInserts, .limiter]))
        precondition(!BusProcessingStage.isValid([.eq, .eq, .fader, .postInserts, .limiter]))
        for position in BusEQPosition.allCases {
            let order = position.order
            precondition(BusProcessingStage.isValid(order))
            precondition(order.firstIndex(of: .eq)! < order.firstIndex(of: .preInserts)! || order.firstIndex(of: .eq)! > order.firstIndex(of: .postInserts)!)
            precondition(try! JSONDecoder().decode(BusEQPosition.self, from: JSONEncoder().encode(position)) == position)
        }
        precondition(BusEQPosition.afterInserts.order == BusEQPosition.beforeLimiter.order)
        precondition(BusEQPosition.migrated([.preInserts,.eq,.fader,.postInserts,.limiter]) == .beforeLimiter)
        let dsp = BusDSP()
        var quiet = [Float](repeating: 0.2, count: 1024)
        quiet.withUnsafeMutableBufferPointer { dsp.processLimiter(buffer: $0.baseAddress!, frames: 512, sampleRate: 48000) }
        precondition(quiet.allSatisfy { $0 == 0.2 } && dsp.limiterReductionDB == 0)
        var loud = (0..<1024).map { $0 % 2 == 0 ? Float(4) : Float(-4) }
        loud.withUnsafeMutableBufferPointer { dsp.processLimiter(buffer: $0.baseAddress!, frames: 512, sampleRate: 48000, thresholdDB: -12, ceilingDB: -6) }
        precondition(loud.allSatisfy { abs($0) <= powf(10, -6 / 20) + 0.00001 })
        precondition(loud[0] > 0 && loud[1] < 0 && dsp.limiterReductionDB > 10)
        for _ in 0..<16 { quiet.withUnsafeMutableBufferPointer { dsp.processLimiter(buffer: $0.baseAddress!, frames: 512, sampleRate: 48000) } }
        precondition(dsp.limiterReductionDB == 0, "Reduction indicator must clear after brief display hold")
        var bypass = [Float](repeating: 4, count: 1024)
        bypass.withUnsafeMutableBufferPointer { dsp.processLimiter(buffer: $0.baseAddress!, frames: 512, sampleRate: 48000, enabled: false) }
        precondition(bypass[0] == 4 && dsp.limiterReductionDB == 0)
        // Streaming lookahead must preserve exact delay across arbitrary callback boundaries,
        // link stereo gain and stay below the sample ceiling at every supported delay/rate.
        for rate: Float in [44100,48000,96000,192000] {
            for ms in [1.0,3,5,10,20] {
                let linked = BusDSP(), delay = BusDSP.limiterLatency(sampleRate:rate,milliseconds:ms)
                var input = [Float](repeating:0,count:(delay+2000)*2)
                input[0] = 4; input[1] = 1
                for n in 1..<(input.count/2) { input[n*2] = sinf(Float(n)*0.07)*2; input[n*2+1] = input[n*2]*0.25 }
                var output = [Float](); var start = 0
                while start < input.count/2 {
                    let count = min(137,input.count/2-start)
                    var block = Array(input[(start*2)..<((start+count)*2)])
                    block.withUnsafeMutableBufferPointer { linked.processLimiter(buffer:$0.baseAddress!,frames:count,sampleRate:rate,thresholdDB:-12,ceilingDB:-6,lookaheadMS:ms) }
                    output.append(contentsOf:block); start += count
                }
                precondition(output.prefix(delay*2).allSatisfy { $0 == 0 })
                precondition(output[delay*2] > 0 && abs(output[delay*2+1]/output[delay*2]-0.25)<0.00001)
                precondition(output.allSatisfy { $0.isFinite && abs($0)<=powf(10,-6/20)+0.00001 })
                for n in delay..<(output.count/2) { precondition(abs(output[n*2+1]-output[n*2]*0.25)<0.00001) }
                var off = [Float](repeating:0.2,count:274)
                off.withUnsafeMutableBufferPointer { linked.processLimiter(buffer:$0.baseAddress!,frames:137,sampleRate:rate,lookaheadMS:0) }
                precondition(off.allSatisfy { $0==0.2 }, "OFF must immediately restore zero-latency legacy processing")
            }
        }
        let timing = AudiomeeterEngine()
        try timing.configureClock(rate:48000,frames:512)
        timing.outputBusAlignmentEnabled = true
        timing.updateBusSettings(bus:.B1) { $0.limiterLookaheadMS = 5 }
        _ = timing.renderOffline()
        precondition(timing.compensationSamples(target:.bus(.A1)) == 240, "Lookahead must participate in output bus alignment")
        timing.outputBusAlignmentEnabled = false
        _ = timing.renderOffline()
        precondition(timing.compensationSamples(target:.bus(.A1)) == 0)
        print("Lookahead limiter passed: streaming latency, ceiling, stereo link, OFF and bus alignment")
        func render(_ order: [BusProcessingStage]) throws -> Float {
            let engine = AudiomeeterEngine()
            try engine.configureClock(rate: 48000, frames: 512)
            engine.busProcessingOrder = order
            for strip in StripID.allCases { engine.updateStripSettings(strip: strip) { $0.routing = RoutingMatrix(); $0.dynamics = DynamicsConfig() } }
            engine.updateStripSettings(strip: .virtualVAIO) { $0.routing = RoutingMatrix(a1: true) }
            engine.updateBusSettings(bus: .A1) { $0.gainDB = -12; $0.limiterThresholdDB = -12; $0.limiterCeilingDB = -6 }
            var result: Float = 0
            for _ in 0..<12 {
                engine.feedOffline(.virtualVAIO, [Float](repeating: 2, count: 1024))
                result = engine.renderOffline()[.A1]![1000]
            }
            return result
        }
        let afterFader = try render(BusProcessingStage.standard)
        let beforeFader = try render([.preInserts, .eq, .limiter, .fader, .postInserts])
        precondition(afterFader > beforeFader * 2, "Actual mixer must apply configured limiter order, not just reorder UI")
        let padEngine = AudiomeeterEngine()
        try padEngine.configureClock(rate: 48000, frames: 512)
        for strip in StripID.allCases { padEngine.updateStripSettings(strip: strip) { $0.routing = RoutingMatrix() } }
        padEngine.updateStripSettings(strip: .hardware1) { $0.routing = RoutingMatrix(a1: true); $0.padMode = .pitch }
        padEngine.updateBusSettings(bus: .A1) { $0.isLimiterEnabled = false }
        var impulse = [Float](repeating:0,count:1024); impulse[0] = 0.1; impulse[1] = 0.1
        // Input playback deliberately waits for a three-block clock reserve.
        // Prime it before measuring the PAD's own delay, rather than measuring silence.
        padEngine.feedOffline(.hardware1, impulse + [Float](repeating:0,count:2048))
        let padOutput = padEngine.renderOffline()[.A1]!
        let peak = stride(from:0,to:padOutput.count,by:2).max(by: { abs(padOutput[$0]) < abs(padOutput[$1]) })!
        precondition(peak/2 == 482, "Pitch PAD nominal delay must reach mixer output")
        print("Bus stages passed: PRE/FADER/POST constraints, limiter ceiling/bypass/indicator hold, actual mixer order")
    }
}
