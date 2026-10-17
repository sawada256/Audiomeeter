import Foundation

/// A preallocated stereo delay. Only touched by the master callback or with IO stopped.
/// Storage comes from calloc, so its zero pages are committed only once a nonzero
/// delay actually writes them; most of the mixer's delay lines stay at zero delay.
final class StereoDelayLine {
    static let maximum = 1048576
    private let capacity = maximum + 4097
    private let samples: UnsafeMutablePointer<Float>
    private var position = 0
    private var valid = 0 // Frames of real history behind position.
    init() {
        samples = calloc(capacity * 2, MemoryLayout<Float>.size)!.assumingMemoryBound(to: Float.self)
    }
    deinit { free(samples) }
    /// Logical reset: older history is never read again, so no memory has to be touched.
    func reset() { position = 0; valid = 0 }
    func process(_ buffer: UnsafeMutablePointer<Float>, frames: Int, delay: Int) {
        let delay = max(0, min(Self.maximum, delay))
        // Pass-through. A later delay increase reads silence, not audio from an older pause.
        guard delay > 0 else { valid = 0; return }
        for frame in 0..<frames {
            let read = (position + capacity - delay) % capacity
            let left = buffer[frame*2], right = buffer[frame*2+1]
            if valid >= delay {
                buffer[frame*2] = samples[read*2]; buffer[frame*2+1] = samples[read*2+1]
            } else { buffer[frame*2] = 0; buffer[frame*2+1] = 0 }
            samples[position*2] = left; samples[position*2+1] = right
            position = (position + 1) % capacity
            if valid < capacity { valid += 1 }
        }
    }
}
