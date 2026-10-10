import Foundation

/// A preallocated stereo delay. Only touched by the master callback or with IO stopped.
final class StereoDelayLine {
    static let maximum = 1048576
    private let capacity = maximum + 4097
    private let samples: UnsafeMutablePointer<Float>
    private var position = 0
    init() {
        samples = .allocate(capacity: capacity * 2)
        samples.initialize(repeating: 0, count: capacity * 2)
    }
    deinit { samples.deallocate() }
    func reset() { samples.update(repeating: 0, count: capacity * 2); position = 0 }
    func process(_ buffer: UnsafeMutablePointer<Float>, frames: Int, delay: Int) {
        let delay = max(0, min(Self.maximum, delay))
        for frame in 0..<frames {
            let read = (position + capacity - delay) % capacity
            samples[position*2] = buffer[frame*2]; samples[position*2+1] = buffer[frame*2+1]
            buffer[frame*2] = samples[read*2]; buffer[frame*2+1] = samples[read*2+1]
            position = (position + 1) % capacity
        }
    }
}
