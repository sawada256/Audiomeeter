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
        padEngine.feedOffline(.hardware1, impulse)
        let padOutput = padEngine.renderOffline()[.A1]!
        let peak = stride(from:0,to:padOutput.count,by:2).max(by: { abs(padOutput[$0]) < abs(padOutput[$1]) })!
        precondition(peak/2 == 482, "Pitch PAD nominal delay must reach mixer output")
        print("Bus stages passed: PRE/FADER/POST constraints, limiter ceiling/bypass/indicator hold, actual mixer order")
    }
}
