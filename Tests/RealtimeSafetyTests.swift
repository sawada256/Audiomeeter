import Foundation
@main struct RealtimeSafetyTests {
    static func main() throws {
        // Delay lines: zero delay is a pure pass-through and never replays old audio later.
        let line = StereoDelayLine()
        var block = (0..<16).map { Float($0 + 1) }
        block.withUnsafeMutableBufferPointer { line.process($0.baseAddress!, frames: 8, delay: 0) }
        precondition(block == (0..<16).map { Float($0 + 1) })
        block = (0..<16).map { Float(100 + $0) }
        block.withUnsafeMutableBufferPointer { line.process($0.baseAddress!, frames: 8, delay: 3) }
        precondition(block[0..<6].allSatisfy { $0 == 0 } && block[6] == 100 && block[7] == 101 && block[15] == 109,
                     "A delay increase after pass-through must read silence, then the new signal")
        line.reset()
        block = [Float](repeating: 7, count: 16)
        block.withUnsafeMutableBufferPointer { line.process($0.baseAddress!, frames: 8, delay: 2) }
        precondition(block[0..<4].allSatisfy { $0 == 0 } && block[4] == 7, "Logical reset discards history")

        // Meter ballistics are time-based: the same duration decays equally at any block size.
        var silent = [Float](repeating: 0, count: 8192)
        var small = MeterLevel(leftPeakDB: 0, rightPeakDB: 0), large = small
        silent.withUnsafeMutableBufferPointer { buffer in
            for _ in 0..<32 { small = MeterCalculator.compute(buffer: buffer.baseAddress!, frames: 64, previousPeakL: small.leftPeakDB, previousPeakR: small.rightPeakDB, sampleRate: 48000) }
            for _ in 0..<4 { large = MeterCalculator.compute(buffer: buffer.baseAddress!, frames: 512, previousPeakL: large.leftPeakDB, previousPeakR: large.rightPeakDB, sampleRate: 48000) }
        }
        precondition(abs(small.leftPeakDB - large.leftPeakDB) < 0.001 && abs(large.leftPeakDB + 9.6) < 0.001, "\(small.leftPeakDB) \(large.leftPeakDB)")
        var tone = (0..<512).map { $0 % 2 == 0 ? Float(0.5) : Float(-0.25) }
        let level = tone.withUnsafeMutableBufferPointer { MeterCalculator.compute(buffer: $0.baseAddress!, frames: 256, previousPeakL: -100, previousPeakR: -100) }
        precondition(abs(level.leftPeakDB - 20 * log10f(0.5)) < 0.001 && abs(level.rightRMSDB - 20 * log10f(0.25)) < 0.001)

        // Settings snapshots: every update reaches the render callback even though the
        // previous snapshot is retired (and freed) outside the callback.
        let engine = AudiomeeterEngine()
        try engine.configureClock(rate: 48000, frames: 256)
        for strip in StripID.allCases { engine.updateStripSettings(strip: strip) { $0.routing = RoutingMatrix(); $0.dynamics = DynamicsConfig() } }
        engine.updateStripSettings(strip: .virtualVAIO) { $0.routing = RoutingMatrix(a1: true) }
        let input = [Float](repeating: 0.25, count: 512)
        func render() -> Float { engine.feedOffline(.virtualVAIO, input); return engine.renderOffline()[.A1]!.last! }
        for _ in 0..<6 { _ = render() }
        precondition(abs(render() - 0.25) < 0.0001, "Routed input must reach A1")
        for step in 0..<5 {
            engine.updateStripSettings(strip: .virtualVAIO) { $0.isMuted = step % 2 == 0 }
            _ = render(); _ = render() // Gain ramps within one block; the second is settled.
            let value = render()
            precondition(step % 2 == 0 ? abs(value) < 0.00001 : abs(value - 0.25) < 0.0001, "Update \(step) was not applied: \(value)")
        }
        engine.updateBusSettings(bus: .A1) { $0.isMuted = true }
        _ = render(); _ = render()
        precondition(abs(render()) < 0.00001, "Bus updates must also be adopted")

        // Whole-chain switches are an atomic mask that round-trips as a set.
        engine.disabledInsertTargets = [.bus(.A2), .strip(.hardware3)]
        precondition(engine.disabledInsertTargets == [.bus(.A2), .strip(.hardware3)])
        engine.disabledInsertTargets.remove(.bus(.A2))
        precondition(engine.disabledInsertTargets == [.strip(.hardware3)])
        print("Realtime safety passed: lazy delay lines, time-based meter decay, retired settings snapshots, atomic chain mask")
    }
}
