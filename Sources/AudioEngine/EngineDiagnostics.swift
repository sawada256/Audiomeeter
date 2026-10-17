import Foundation

/// Snapshot for the diagnostics window, gathered on the main thread from atomics.
struct EngineDiagnostics {
    enum PathMode: String { case none, master, direct, ring, internalReturn }
    struct Path: Identifiable {
        var name: String
        var mode = PathMode.none
        var fill: Float = 0
        var underruns: UInt64 = 0
        var overflows: UInt64 = 0
        var correctionPPM: Double = 0
        var latency = 0 // Plugin/PDC samples at the path output.
        var id: String { name }
    }
    struct Plugin: Identifiable {
        var id: UUID
        var target: String
        var name: String
        var latency: Int
        var lateBlocks: UInt64
        var renderMicros: Double
        var restarts: Int
        var status: String
    }
    var running = false
    var usingFallbackClock = false
    var sampleRate = 48000.0
    var bufferFrames = 256
    var cycles: UInt64 = 0
    var cycleMicros = 0.0
    var cycleMaxMicros = 0.0
    var cycleOverruns: UInt64 = 0
    var masterLatency = 0
    var inputs: [Path] = []
    var outputs: [Path] = []
    var plugins: [Plugin] = []
    var recordingDroppedFrames: UInt64 = 0
    var playbackUnderruns: UInt64 = 0
    var blockMicros: Double { Double(bufferFrames) / max(1, sampleRate) * 1_000_000 }
    var load: Double { cycleMicros / max(1, blockMicros) }
}
