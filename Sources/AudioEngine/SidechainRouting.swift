import Foundation

/// Ten processing nodes: five input strips followed by five output buses.
/// Only sidechain edges inside a cycle use history; ordinary mixer edges stay current.
struct SidechainRenderGraph {
    let routingEdges: [UInt16]
    let sidechainEdges: [UInt16]
    let order: [Int]
    private let feedbackEdges: [UInt16]

    static func node(_ target: InsertTarget) -> Int {
        switch target { case .strip(let strip): return strip.rawValue; case .bus(let bus): return 5 + bus.rawValue }
    }
    static func target(_ node: Int) -> InsertTarget {
        node < 5 ? .strip(StripID(rawValue: node)!) : .bus(BusID(rawValue: node - 5)!)
    }
    init(routingEdges: [UInt16], sidechainEdges: [UInt16]) {
        self.routingEdges = routingEdges; self.sidechainEdges = sidechainEdges
        var reachable = zip(routingEdges, sidechainEdges).map { $0 | $1 }
        for intermediate in 0..<10 {
            for source in 0..<10 where reachable[source] & (1 << intermediate) != 0 {
                reachable[source] |= reachable[intermediate]
            }
        }
        var feedback = [UInt16](repeating: 0, count: 10)
        var forward = routingEdges
        for source in 0..<10 {
            for destination in 0..<10 where sidechainEdges[source] & (1 << destination) != 0 {
                if source == destination || reachable[destination] & (1 << source) != 0 {
                    feedback[source] |= 1 << destination
                } else { forward[source] |= 1 << destination }
            }
        }
        feedbackEdges = feedback
        var incoming = [UInt16](repeating: 0, count: 10)
        for source in 0..<10 {
            for destination in 0..<10 where forward[source] & (1 << destination) != 0 {
                incoming[destination] |= 1 << source
            }
        }
        var remaining: UInt16 = (1 << 10) - 1
        var sorted: [Int] = []; sorted.reserveCapacity(10)
        while remaining != 0 {
            guard let next = (0..<10).first(where: { remaining & (1 << $0) != 0 && incoming[$0] & remaining == 0 }) else {
                preconditionFailure("Mixer graph must be acyclic after cutting feedback sidechains")
            }
            sorted.append(next); remaining &= ~(1 << next)
        }
        order = sorted
    }
    init(strips: [StripID: StripSettings], inserts: [InsertTarget: [InsertConfig]]) {
        var routing = [UInt16](repeating: 0, count: 10), sidechains = routing
        for strip in StripID.allCases {
            for bus in BusID.allCases where strips[strip]?.routing[bus] == true {
                routing[strip.rawValue] |= 1 << (5 + bus.rawValue)
            }
        }
        for (target, slots) in inserts {
            for slot in slots where !slot.bypassed {
                if let bus = slot.sidechainBus { sidechains[5 + bus.rawValue] |= 1 << Self.node(target) }
            }
        }
        self.init(routingEdges: routing, sidechainEdges: sidechains)
    }
    func usesPreviousBlock(source: BusID, target: InsertTarget) -> Bool {
        feedbackEdges[5 + source.rawValue] & (1 << Self.node(target)) != 0
    }
}

/// Stores each processed input once, with independent reads for bus-specific PDC.
/// Sharing history avoids allocating a delay line for all 25 mixer connections.
final class StereoSampleHistory {
    private let capacity = StereoDelayLine.maximum + 4097
    private let samples: UnsafeMutablePointer<Float>
    private var position = 0
    init() {
        samples = .allocate(capacity: capacity * 2)
        samples.initialize(repeating: 0, count: capacity * 2)
    }
    deinit { samples.deallocate() }
    func reset() { samples.update(repeating: 0, count: capacity * 2); position = 0 }
    func write(_ buffer: UnsafePointer<Float>, frames: Int) {
        for frame in 0..<frames {
            samples[position * 2] = buffer[frame * 2]; samples[position * 2 + 1] = buffer[frame * 2 + 1]
            position = (position + 1) % capacity
        }
    }
    func read(into buffer: UnsafeMutablePointer<Float>, frames: Int, delay: Int) {
        var read = (position + capacity - frames - min(StereoDelayLine.maximum, max(0, delay))) % capacity
        for frame in 0..<frames {
            buffer[frame * 2] = samples[read * 2]; buffer[frame * 2 + 1] = samples[read * 2 + 1]
            read = (read + 1) % capacity
        }
    }
}
