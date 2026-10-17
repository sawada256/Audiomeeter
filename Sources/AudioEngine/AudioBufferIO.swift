import CoreAudio

/// Core Audio Float32 buffers may contain one interleaved stream, planar
/// channels, or several interleaved stream groups. Respect each group's stride.
enum StereoAudioBufferIO {
    private static func channel(_ index: Int, in buffers: UnsafeMutableAudioBufferListPointer) -> (UnsafeMutablePointer<Float>, Int, Int)? {
        var offset = 0
        for buffer in buffers {
            let channels = Int(buffer.mNumberChannels)
            if index >= offset, index < offset + channels, channels > 0,
               let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                return (data.advanced(by: index - offset), channels, Int(buffer.mDataByteSize) / (4 * channels))
            }
            offset += channels
        }
        return nil
    }

    static func frameCount(_ data: UnsafeMutablePointer<AudioBufferList>) -> Int {
        let buffers = UnsafeMutableAudioBufferListPointer(data)
        return channel(0, in: buffers)?.2 ?? 0
    }

    static func clear(_ data: UnsafeMutablePointer<AudioBufferList>) {
        for buffer in UnsafeMutableAudioBufferListPointer(data) {
            if let pointer = buffer.mData { memset(pointer, 0, Int(buffer.mDataByteSize)) }
        }
    }

    static func read(_ data: UnsafePointer<AudioBufferList>, into stereo: UnsafeMutablePointer<Float>, capacity: Int, channelOffset: Int = 0, leftChannel: Int? = nil, rightChannel: Int? = nil) -> Int {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: data))
        let left = leftChannel.map { channel($0, in: buffers) } ?? (channel(max(0, channelOffset), in: buffers) ?? channel(0, in: buffers))
        let right = rightChannel.map { channel($0, in: buffers) } ?? (channel(max(0, channelOffset) + 1, in: buffers) ?? channel(1, in: buffers) ?? left)
        guard let available = left ?? right else {
            let frames = min(max(0, capacity), channel(0, in: buffers)?.2 ?? 0)
            stereo.initialize(repeating: 0, count: frames * 2)
            return frames
        }
        let frames = min(max(0, capacity), left?.2 ?? available.2, right?.2 ?? available.2)
        for frame in 0..<frames {
            stereo[frame * 2] = left.map { $0.0[frame * $0.1] } ?? 0
            stereo[frame * 2 + 1] = right.map { $0.0[frame * $0.1] } ?? 0
        }
        return frames
    }

    /// `clearFirst: false` adds another bus on different channels of a buffer already written this cycle.
    static func write(_ stereo: UnsafePointer<Float>, frames: Int, to data: UnsafeMutablePointer<AudioBufferList>, channelOffset: Int = 0, leftChannel: Int? = nil, rightChannel: Int? = nil, clearFirst: Bool = true) {
        if clearFirst { clear(data) }
        let buffers = UnsafeMutableAudioBufferListPointer(data)
        let left = leftChannel.map { channel($0, in: buffers) } ?? (channel(max(0, channelOffset), in: buffers) ?? channel(0, in: buffers))
        let right = rightChannel.map { channel($0, in: buffers) } ?? (channel(max(0, channelOffset) + 1, in: buffers) ?? channel(1, in: buffers))
        if let left, let right, left.0 == right.0 {
            for frame in 0..<max(0, min(frames, left.2)) { left.0[frame * left.1] = (stereo[frame * 2] + stereo[frame * 2 + 1]) * 0.5 }
        } else if let left, right == nil, rightChannel == nil {
            for frame in 0..<max(0, min(frames, left.2)) { left.0[frame * left.1] = (stereo[frame * 2] + stereo[frame * 2 + 1]) * 0.5 }
        } else {
            if let left { for frame in 0..<max(0, min(frames, left.2)) { left.0[frame * left.1] = stereo[frame * 2] } }
            if let right { for frame in 0..<max(0, min(frames, right.2)) { right.0[frame * right.1] = stereo[frame * 2 + 1] } }
        }
    }
}
