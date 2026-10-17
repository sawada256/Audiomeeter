import Foundation

/// Node layout shared by the render graph, latency arrays and node masks:
/// seven input strips (raw values 0...6) followed by seven output buses.
enum MixerTopology {
    static let strips = 7, buses = 7, nodes = 14
    static func node(_ strip: StripID) -> Int { strip.rawValue }
    static func node(_ bus: BusID) -> Int { strips + bus.rawValue }
}

/// Only sidechain edges inside a cycle use history; ordinary mixer edges stay current.
/// `rebuild` works in place on preallocated arrays, so the render callback can
/// update the graph after a routing change without allocating.
struct SidechainRenderGraph {
    private(set) var routingEdges: [UInt16]
    private(set) var sidechainEdges: [UInt16]
    private(set) var order: [Int]
    private var feedbackEdges: [UInt16]
    private var reachable: [UInt16]
    private var forward: [UInt16]
    private var incoming: [UInt16]

    static func node(_ target: InsertTarget) -> Int {
        switch target { case .strip(let strip): return MixerTopology.node(strip); case .bus(let bus): return MixerTopology.node(bus) }
    }
    static func target(_ node: Int) -> InsertTarget {
        node < MixerTopology.strips ? .strip(StripID(rawValue: node)!) : .bus(BusID(rawValue: node - MixerTopology.strips)!)
    }
    init(routingEdges: [UInt16], sidechainEdges: [UInt16]) {
        let empty = [UInt16](repeating: 0, count: MixerTopology.nodes)
        self.routingEdges = empty; self.sidechainEdges = empty; feedbackEdges = empty
        reachable = empty; forward = empty; incoming = empty
        order = []; order.reserveCapacity(MixerTopology.nodes)
        rebuild(routing: routingEdges, sidechains: sidechainEdges)
    }
    func matches(routing: [UInt16], sidechains: [UInt16]) -> Bool { routing == routingEdges && sidechains == sidechainEdges }
    mutating func rebuild(routing: [UInt16], sidechains: [UInt16]) {
        let count = MixerTopology.nodes
        for i in 0..<count {
            routingEdges[i] = i < routing.count ? routing[i] : 0
            sidechainEdges[i] = i < sidechains.count ? sidechains[i] : 0
            reachable[i] = routingEdges[i] | sidechainEdges[i]
            feedbackEdges[i] = 0; forward[i] = routingEdges[i]; incoming[i] = 0
        }
        for intermediate in 0..<count {
            for source in 0..<count where reachable[source] & (1 << intermediate) != 0 {
                reachable[source] |= reachable[intermediate]
            }
        }
        for source in 0..<count {
            for destination in 0..<count where sidechainEdges[source] & (1 << destination) != 0 {
                if source == destination || reachable[destination] & (1 << source) != 0 {
                    feedbackEdges[source] |= 1 << destination
                } else { forward[source] |= 1 << destination }
            }
        }
        for source in 0..<count {
            for destination in 0..<count where forward[source] & (1 << destination) != 0 {
                incoming[destination] |= 1 << source
            }
        }
        var remaining: UInt16 = (1 << UInt16(count)) - 1
        order.removeAll(keepingCapacity: true)
        while remaining != 0 {
            var next = -1
            for candidate in 0..<count where remaining & (1 << candidate) != 0 && incoming[candidate] & remaining == 0 { next = candidate; break }
            precondition(next >= 0, "Mixer graph must be acyclic after cutting feedback sidechains")
            order.append(next); remaining &= ~(1 << UInt16(next))
        }
    }
    init(strips: [StripID: StripSettings], inserts: [InsertTarget: [InsertConfig]]) {
        var routing = [UInt16](repeating: 0, count: MixerTopology.nodes), sidechains = routing
        for strip in StripID.allCases {
            for bus in BusID.allCases where strips[strip]?.routing[bus] == true {
                routing[MixerTopology.node(strip)] |= 1 << MixerTopology.node(bus)
            }
        }
        for (target, slots) in inserts {
            for slot in slots where !slot.isFullyBypassed {
                if let bus = slot.sidechainBus { sidechains[MixerTopology.node(bus)] |= 1 << Self.node(target) }
            }
        }
        self.init(routingEdges: routing, sidechainEdges: sidechains)
    }
    func usesPreviousBlock(source: BusID, target: InsertTarget) -> Bool {
        feedbackEdges[MixerTopology.node(source)] & (1 << Self.node(target)) != 0
    }
}

/// Stores each processed input once, with independent reads for bus-specific PDC.
/// Sharing history avoids allocating a delay line for all mixer connections.
/// calloc-backed: pages are committed only for strips that actually write history.
final class StereoSampleHistory {
    private let capacity = StereoDelayLine.maximum + 4097
    private let samples: UnsafeMutablePointer<Float>
    private var position = 0
    private var valid = 0 // Frames of real history ending at position.
    init() {
        samples = calloc(capacity * 2, MemoryLayout<Float>.size)!.assumingMemoryBound(to: Float.self)
    }
    deinit { free(samples) }
    func reset() { position = 0; valid = 0 }
    /// Drops history without touching memory; later delayed reads return silence.
    func invalidate() { valid = 0 }
    func write(_ buffer: UnsafePointer<Float>, frames: Int) {
        for frame in 0..<frames {
            samples[position * 2] = buffer[frame * 2]; samples[position * 2 + 1] = buffer[frame * 2 + 1]
            position = (position + 1) % capacity
        }
        valid = min(capacity, valid + frames)
    }
    func read(into buffer: UnsafeMutablePointer<Float>, frames: Int, delay: Int) {
        let delay = min(StereoDelayLine.maximum, max(0, delay))
        var read = (position + capacity - frames - delay) % capacity
        for frame in 0..<frames {
            // Frame age (from the newest written frame) must lie within valid history.
            let age = frames + delay - frame
            if age <= valid { buffer[frame * 2] = samples[read * 2]; buffer[frame * 2 + 1] = samples[read * 2 + 1] }
            else { buffer[frame * 2] = 0; buffer[frame * 2 + 1] = 0 }
            read = (read + 1) % capacity
        }
    }
}
