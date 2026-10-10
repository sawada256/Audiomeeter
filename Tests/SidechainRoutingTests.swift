import Foundation

@main struct SidechainRoutingTests {
    static let root = FileManager.default.currentDirectoryPath + "/.build/plugin-host/"
    static func slot(sidechain: BusID? = nil, position: InsertPosition = .post, gain: Bool = false, frames: UInt32 = 512) throws -> HostedInsert {
        var config = InsertConfig(path: root + (gain ? "VMTestGain_artefacts/Release/VST3/Audiomeeter Test Gain.vst3" : "VMTestSide_artefacts/Release/VST3/Audiomeeter Test Sidechain.vst3"), name: "Test", position: position)
        config.sidechainBus = sidechain
        let insert = try HostedInsert(config: config, rate: 48000, block: frames)
        for _ in 0..<500 { insert.refresh(); if insert.status.isEmpty { return insert }; usleep(20000) }
        preconditionFailure(insert.status)
    }
    static func engine(frames: UInt32 = 512) throws -> AudiomeeterEngine {
        let engine = AudiomeeterEngine()
        try engine.configureClock(rate: 48000, frames: frames)
        engine.latencyCompensationEnabled = false
        engine.outputBusAlignmentEnabled = false
        for strip in StripID.allCases { engine.updateStripSettings(strip: strip) { $0.routing = RoutingMatrix(); $0.dynamics = DynamicsConfig() } }
        return engine
    }
    // Prime asynchronous workers, then record a stereo impulse through the actual mixer.
    static func impulses(_ engine: AudiomeeterEngine, main: StripID = .virtualVAIO, source: StripID = .hardware1) -> [BusID: [Float]] {
        let frames = Int(engine.bufferSize), zeros = [Float](repeating: 0, count: frames * 2)
        for _ in 0..<12 { engine.feedOffline(main, zeros); engine.feedOffline(source, zeros); _ = engine.renderOffline(); usleep(12000) }
        var result = Dictionary(uniqueKeysWithValues: BusID.allCases.map { ($0, [Float]()) })
        for block in 0..<32 {
            var a = zeros, b = zeros
            if block == 0 { a[0] = 0.1; a[1] = 0.1; b[0] = 0.2; b[1] = 0.2 }
            engine.feedOffline(main, a); engine.feedOffline(source, b)
            for (bus, samples) in engine.renderOffline() { result[bus]! += stride(from: 0, to: samples.count, by: 2).map { samples[$0] } }
            usleep(12000)
        }
        // Input rings deliberately keep two blocks of device-clock reserve.
        // Compare processing latency from the mixer input, excluding this common IO delay.
        return result.mapValues { Array($0.dropFirst(frames * 2)) }
    }
    static func assertImpulses(_ samples: [Float], _ expected: [(Int, Float)], message: String) {
        let expectedValues = Dictionary(uniqueKeysWithValues: expected)
        for i in samples.indices {
            precondition(abs(samples[i] - (expectedValues[i] ?? 0)) < 0.00001, "\(message): frame \(i) = \(samples[i]), expected \(expectedValues[i] ?? 0)")
        }
    }
    static func sameBlockAndAlignment(frames: UInt32, align: Bool, inputInsert: Bool = false, manual: Int = 0, twoStages: Bool = false) throws {
        let engine = try engine(frames: frames)
        engine.sidechainAlignmentEnabled = align
        engine.updateStripSettings(strip: .virtualVAIO) { $0.routing = RoutingMatrix(a1: true) }
        engine.updateStripSettings(strip: .hardware1) { $0.routing = RoutingMatrix(b1: true) }
        engine.updateBusSettings(bus: .B1) { $0.delayMilliseconds = Double(manual) / 48 }
        let source = try slot(gain: true, frames: frames)
        let receiver = try slot(sidechain: .B1, position: inputInsert || twoStages ? .pre : .post, frames: frames)
        let target: InsertTarget = inputInsert ? .strip(.virtualVAIO) : .bus(.A1)
        engine.inserts[.bus(.B1)] = [source]; engine.inserts[target] = [receiver]
        if twoStages { engine.inserts[target]!.append(try slot(sidechain: .B1, frames: frames)) }
        let result = impulses(engine)[.A1]!
        let sourceLatency = Int(frames) + manual, effectLatency = Int(frames) + 37
        if twoStages {
            assertImpulses(result, [(sourceLatency + 2 * effectLatency, 0.0625)], message: "PRE/POST source timing")
        } else if align {
            assertImpulses(result, [(sourceLatency + effectLatency, 0.075)], message: "Aligned main and bus sidechain")
        } else {
            assertImpulses(result, [(effectLatency, 0.05), (sourceLatency + effectLatency, 0.025)], message: "Unaligned mode must preserve main latency")
        }
        precondition(receiver.alignmentDelaySamples == (align ? sourceLatency : 0))
        print("Current-block bus sidechain: frames=\(frames), alignment=\(align), input=\(inputInsert), manual=\(manual), PRE+POST=\(twoStages) passed")
    }
    static func zeroExtraBlock() throws {
        let engine = try engine()
        engine.sidechainAlignmentEnabled = false
        engine.updateStripSettings(strip: .hardware1) { $0.routing = RoutingMatrix(b1: true) }
        let receiver = try slot(sidechain: .B1)
        engine.inserts[.bus(.A1)] = [receiver]
        // A1 has no main signal, so its output is exactly the B1 sidechain contribution.
        assertImpulses(impulses(engine)[.A1]!, [(549, 0.05)], message: "Acyclic sidechain must not add a history block")
        print("B1 -> A1 with no source plugins: impulse arrives at 549, not 1061 samples")
    }
    static func feedback() throws {
        let engine = try engine()
        engine.updateStripSettings(strip: .virtualVAIO) { $0.routing = RoutingMatrix(a1: true) }
        let a = try slot(sidechain: .B1), b = try slot(sidechain: .A1), branch = try slot(sidechain: .B1)
        engine.inserts[.bus(.A1)] = [a]; engine.inserts[.bus(.B1)] = [b]; engine.inserts[.bus(.A3)] = [branch]
        let result = impulses(engine)
        // In the cycle, each edge contributes exactly one history block plus receiver IPC/latency.
        var expectedA: [(Int, Float)] = [], expectedB: [(Int, Float)] = [], expectedBranch: [(Int, Float)] = []
        var at = 549, amplitude: Float = 0.05
        while at < result[.A1]!.count {
            expectedA.append((at, amplitude)); at += 1061; amplitude *= 0.25
            if at < result[.B1]!.count { expectedB.append((at, amplitude)) }
            if at + 549 < result[.A3]!.count { expectedBranch.append((at + 549, amplitude * 0.25)) }
            at += 1061; amplitude *= 0.25
        }
        assertImpulses(result[.A1]!, expectedA, message: "A1 feedback")
        assertImpulses(result[.B1]!, expectedB, message: "B1 feedback")
        assertImpulses(result[.A3]!, expectedBranch, message: "Acyclic branch from feedback bus")
        precondition(a.alignmentDelaySamples == 0 && b.alignmentDelaySamples == 0 && branch.alignmentDelaySamples == 549)
        print("Mutual bus feedback stays finite; only cyclic edges use history; outgoing branch remains current-block")
    }
    static func graphChecks() {
        var strips: [StripID: StripSettings] = [:]
        var s = StripSettings(); s.routing = RoutingMatrix(a1: true); strips[.virtualVAIO] = s
        var source = StripSettings(); source.routing = RoutingMatrix(b1: true); strips[.hardware1] = source
        var config = InsertConfig(path: "", name: "", position: .pre); config.sidechainBus = .B1
        var inserts: [InsertTarget: [InsertConfig]] = [.strip(.virtualVAIO): [config]]
        var graph = SidechainRenderGraph(strips: strips, inserts: inserts)
        precondition(!graph.usesPreviousBlock(source: .B1, target: .strip(.virtualVAIO)))
        precondition(graph.order.firstIndex(of: 8)! < graph.order.firstIndex(of: 3)!)
        strips[.virtualVAIO]?.routing.b1 = true
        graph = SidechainRenderGraph(strips: strips, inserts: inserts)
        precondition(graph.usesPreviousBlock(source: .B1, target: .strip(.virtualVAIO)))
        inserts[.strip(.virtualVAIO)]![0].bypassed = true
        graph = SidechainRenderGraph(strips: strips, inserts: inserts)
        precondition(!graph.usesPreviousBlock(source: .B1, target: .strip(.virtualVAIO)))
        config.sidechainBus = .A1
        graph = SidechainRenderGraph(strips: [:], inserts: [.bus(.A1): [config]])
        precondition(graph.usesPreviousBlock(source: .A1, target: .bus(.A1)))
        print("Input/bus cycles, self-feedback, bypassed edges, and topological processing order passed")
    }
    static func independentOutputAlignment() throws {
        let mixer = try engine()
        mixer.sidechainAlignmentEnabled = false
        mixer.updateStripSettings(strip: .virtualVAIO) { $0.routing = RoutingMatrix(a1: true) }
        mixer.updateStripSettings(strip: .hardware1) { $0.routing = RoutingMatrix(b1: true) }
        mixer.inserts[.bus(.B1)] = [try slot(gain: true)]
        for enabled in [false, true, false] {
            mixer.outputBusAlignmentEnabled = enabled
            let result = impulses(mixer)
            assertImpulses(result[.A1]!, [(enabled ? 512 : 0, 0.1)], message: "Unrelated B1 must delay A1 only with output synchronization ON")
            assertImpulses(result[.B1]!, [(512, 0.1)], message: "B1 must retain its own plugin latency")
        }
        mixer.latencyCompensationEnabled = true
        mixer.updateStripSettings(strip: .hardware1) { $0.routing = RoutingMatrix(a1: true, b1: true) }
        mixer.inserts[.strip(.hardware1)] = [try slot(gain: true)]
        for enabled in [false, true] {
            mixer.outputBusAlignmentEnabled = enabled
            let result = impulses(mixer)
            assertImpulses(result[.A1]!, [(enabled ? 1024 : 512, 0.2)], message: "Input summing must stay aligned with output synchronization OFF")
            assertImpulses(result[.B1]!, [(1024, 0.05)], message: "Input and B1 plugin delays must remain intact")
        }
        print("Independent output synchronization toggles without losing input alignment or plugin latency")
    }
    static func main() throws {
        graphChecks()
        try independentOutputAlignment()
        try zeroExtraBlock()
        try sameBlockAndAlignment(frames: 512, align: false)
        try sameBlockAndAlignment(frames: 512, align: true)
        try sameBlockAndAlignment(frames: 256, align: true, inputInsert: true, manual: 120)
        try sameBlockAndAlignment(frames: 512, align: true, manual: 120, twoStages: true)
        try feedback()
        let mixer = try engine()
        mixer.updateStripSettings(strip: .virtualVAIO) { $0.routing = RoutingMatrix(a1: true) }
        let effect = try slot(sidechain: .B1)
        mixer.inserts[.bus(.A1)] = [effect]
        let original = effect.config
        mixer.disabledInsertTargets.insert(.bus(.A1))
        assertImpulses(impulses(mixer)[.A1]!, [(0, 0.1)], message: "Whole-chain bypass must route dry audio")
        precondition(mixer.insertLatency(.bus(.A1)) == 0 && effect.config == original)
        mixer.disabledInsertTargets.remove(.bus(.A1))
        assertImpulses(impulses(mixer)[.A1]!, [(549, 0.05)], message: "Re-enabled chain must retain its plugin")
        precondition(effect.config == original && mixer.insertLatency(.bus(.A1)) == 549)
        print("Whole-chain bypass/re-enable preserves plugin state and individual bypass settings")
    }
}
