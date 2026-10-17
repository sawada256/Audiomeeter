import Foundation
import CoreAudio
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
        engine.disabledInsertTargets = []
        engine.updateBusSettings(bus: .A1) { $0.isMuted = false }

        // Bus stage order is packed into one atomic word.
        for position in BusEQPosition.allCases {
            engine.busProcessingOrder = position.order
            precondition(engine.busProcessingOrder == position.order)
        }
        engine.busProcessingOrder = BusProcessingStage.standard

        // Optional strips/buses (IN 4/5, A4/A5) are full graph nodes.
        engine.updateStripSettings(strip: .virtualVAIO) { $0.routing = RoutingMatrix(a5: true); $0.isMuted = false }
        for _ in 0..<4 { _ = render() }
        engine.feedOffline(.virtualVAIO, input)
        let buses = engine.renderOffline()
        precondition(abs(buses[.A5]!.last! - 0.25) < 0.0001 && abs(buses[.A1]!.last!) < 0.00001, "VAIO -> A5 only")
        precondition(SidechainRenderGraph(strips: [.hardware5: StripSettings(routing: RoutingMatrix(a4: true))], inserts: [:]).order.count == MixerTopology.nodes)

        // Same-device IO: an input and a secondary bus on the A1 device are served inside
        // the master callback (no ring priming), on their own channels of the master buffer.
        let direct = AudiomeeterEngine()
        try direct.configureClock(rate: 48000, frames: 256)
        direct.setOfflineMaster(4242)
        let device = AudioDeviceInfo(id: 4242, name: "Interface", uid: "interface", inChannels: 4, outChannels: 4, sampleRate: 48000)
        for strip in StripID.allCases { direct.updateStripSettings(strip: strip) { $0.routing = RoutingMatrix(); $0.dynamics = DynamicsConfig() } }
        direct.updateStripSettings(strip: .hardware2) { $0.routing = RoutingMatrix(a1: true, a2: true); $0.leftChannel = 2; $0.rightChannel = 3; $0.padMode = .pan }
        direct.assignInputDevice(strip: .hardware2, device: device)
        direct.updateStripSettings(strip: .hardware2) { $0.leftChannel = 2; $0.rightChannel = 3 }
        direct.updateBusSettings(bus: .A2) { $0.leftChannel = 2; $0.rightChannel = 3 }
        direct.assignOutputDevice(bus: .A2, device: device)
        let frames = 256
        let inputSamples = UnsafeMutablePointer<Float>.allocate(capacity: frames * 4), outputSamples = UnsafeMutablePointer<Float>.allocate(capacity: frames * 4)
        defer { inputSamples.deallocate(); outputSamples.deallocate() }
        for frame in 0..<frames { for channel in 0..<4 { inputSamples[frame * 4 + channel] = channel == 2 ? 0.3 : channel == 3 ? -0.2 : 0.9 } }
        var inputList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 4, mDataByteSize: UInt32(frames * 16), mData: inputSamples))
        var outputList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 4, mDataByteSize: UInt32(frames * 16), mData: outputSamples))
        direct.renderOfflineDevice(input: &inputList, output: &outputList)
        let last = (frames - 1) * 4
        precondition(abs(outputSamples[last] - 0.3) < 0.0001 && abs(outputSamples[last + 1] + 0.2) < 0.0001, "A1 must carry the direct input in the first block")
        precondition(abs(outputSamples[last + 2] - 0.3) < 0.0001 && abs(outputSamples[last + 3] + 0.2) < 0.0001, "A2 must be written to channels 3/4 without clearing A1")
        let report = direct.diagnostics(resetPeak: true)
        precondition(report.inputs.first { $0.name == StripID.hardware2.shortName }?.mode == .direct && report.outputs.first { $0.name == "A2" }?.mode == .direct)

        // EQ coefficient changes glide over one block, then settle on the new response.
        var filter = BiquadFilter()
        var dc = [Float](repeating: 1, count: 512)
        filter.setLowShelf(sampleRate: 48000, cutoffHz: 1000, gainDB: 0)
        dc.withUnsafeMutableBufferPointer { filter.processBlock($0.baseAddress!, frames: 256) }
        filter.setLowShelf(sampleRate: 48000, cutoffHz: 1000, gainDB: 12)
        dc = [Float](repeating: 1, count: 512)
        dc.withUnsafeMutableBufferPointer { filter.processBlock($0.baseAddress!, frames: 256) }
        precondition(abs(dc[0] - 1) < 0.05, "First sample after a change must stay near the old response")
        var largestStep: Float = 0
        for i in 1..<256 { largestStep = max(largestStep, abs(dc[i * 2] - dc[(i - 1) * 2])) }
        precondition(largestStep < 0.1 && filter.isSettled, "Coefficient ramp must be smooth and finish within the block (\(largestStep))")
        for _ in 0..<40 { dc = [Float](repeating: 1, count: 512); dc.withUnsafeMutableBufferPointer { filter.processBlock($0.baseAddress!, frames: 256) } }
        precondition(abs(dc[510] - powf(10, 12.0 / 20)) < 0.02, "Settles on the new +12 dB DC response: \(dc[510])")

        // Chain snapshots: a removed insert is released once the callback cannot hold it.
        let root = FileManager.default.currentDirectoryPath + "/.build/plugin-host/"
        weak var released: HostedInsert?
        do {
            let slot = try HostedInsert(config: InsertConfig(path: root + "VMTestGain_artefacts/Release/VST3/Audiomeeter Test Gain.vst3", name: "Gain", position: .post), rate: 48000, block: 256)
            released = slot
            engine.inserts[.bus(.A5)] = [slot]
            _ = render()
            engine.inserts = [:]
        }
        precondition(released == nil, "Stopped engine releases retired snapshots immediately")

        // Live edits: the engine renders on its timer thread while the main thread republishes
        // chains and flips atomic options. Retired snapshots are released only after later cycles.
        let live = AudiomeeterEngine()
        try live.configureClock(rate: 48000, frames: 128)
        weak var liveSlot: HostedInsert?
        do {
            let slot = try HostedInsert(config: InsertConfig(path: root + "VMTestGain_artefacts/Release/VST3/Audiomeeter Test Gain.vst3", name: "Gain", position: .pre), rate: 48000, block: 128)
            liveSlot = slot
            live.start()
            for step in 0..<400 {
                live.inserts = step % 2 == 0 ? [.bus(.A1): [slot], .strip(.virtualVAIO): [slot]] : [:]
                live.disabledInsertTargets = step % 3 == 0 ? [.bus(.A1)] : []
                live.busProcessingOrder = BusEQPosition.allCases[step % 4].order
                live.latencyCompensationEnabled = step % 5 != 0
                slot.setBypass(step % 7 == 0 ? .full : step % 7 == 1 ? .latency : nil)
                usleep(700)
                live.reclaimRetiredChains()
            }
            live.inserts = [:]
            let beat = live.renderHeartbeat
            let deadline = Date().addingTimeInterval(2)
            while live.renderHeartbeat < beat + 3 && Date() < deadline { usleep(2000) }
            precondition(live.renderHeartbeat >= beat + 3, "Timer-driven rendering must keep running during edits")
            live.reclaimRetiredChains()
        }
        precondition(liveSlot == nil, "Retired snapshots must be released once the callback has moved on")
        live.stop()
        print("Realtime safety passed: lazy delay lines, meter decay, retired settings, atomic chain mask/stage order, A4/A5 nodes, same-device direct IO, EQ ramp, snapshot reclaim")
    }
}
