import Foundation
import Darwin
import VMNative

/// High-performance Lock-Free SPSC (Single Producer Single Consumer) Stereo Audio Ring Buffer
public final class StereoRingBuffer {
    private let capacityFrames: Int
    private let mask: Int
    private let channels: Int = 2

    private let buffer: UnsafeMutablePointer<Float>
    private let readCounter = vm_counter_create()!
    private var readIndex: UInt64 {
        get { vm_counter_load(readCounter) }
        set { vm_counter_store(readCounter, newValue) }
    }
    private let writeCounter = vm_counter_create()!
    private var writeIndex: UInt64 {
        get { vm_counter_load(writeCounter) }
        set { vm_counter_store(writeCounter, newValue) }
    }
    // Accessed only by the consumer; reset requires stopped IO.
    private var playbackPrimed = false

    public init(capacityFrames: Int = 16384) {
        // Ensure capacity is a power of 2 for fast bitwise masking
        var cap = 1
        while cap < capacityFrames {
            cap <<= 1
        }
        self.capacityFrames = cap
        self.mask = cap - 1
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: cap * 2)
        self.buffer.initialize(repeating: 0.0, count: cap * 2)
    }

    deinit {
        buffer.deallocate()
        vm_counter_destroy(readCounter)
        vm_counter_destroy(writeCounter)
    }

    public func reset() {
        playbackPrimed = false
        readIndex = writeIndex
        buffer.initialize(repeating: 0.0, count: capacityFrames * 2)
    }

    @inline(__always)
    public func availableRead() -> Int {
        let w = writeIndex
        let r = readIndex
        if w >= r {
            return Int(w - r)
        } else {
            return 0
        }
    }

    @inline(__always)
    public func availableWrite() -> Int {
        return capacityFrames - availableRead()
    }

    @inline(__always)
    public func fillRatio() -> Float {
        return Float(availableRead()) / Float(capacityFrames)
    }

    /// Write stereo interleaved frames into the ring buffer
    @discardableResult
    public func write(from source: UnsafePointer<Float>, frameCount: Int) -> Int {
        let avail = availableWrite()
        let toWrite = min(frameCount, avail)
        if toWrite <= 0 { return 0 }

        let currentWrite = Int(writeIndex & UInt64(mask))
        let firstPart = min(toWrite, capacityFrames - currentWrite)
        let secondPart = toWrite - firstPart

        // Copy first chunk
        memcpy(buffer.advanced(by: currentWrite * 2), source, firstPart * 2 * MemoryLayout<Float>.size)

        // Wrap-around copy if needed
        if secondPart > 0 {
            memcpy(buffer, source.advanced(by: firstPart * 2), secondPart * 2 * MemoryLayout<Float>.size)
        }

        writeIndex &+= UInt64(toWrite)
        return toWrite
    }

    /// Keep a small reserve between independent device clocks. Waiting must not
    /// consume a partial block, otherwise the reserve can never accumulate.
    /// Recording uses read() directly and does not incur this playback delay.
    @discardableResult
    public func readForPlayback(into destination: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
        guard frameCount > 0 else { return 0 }
        let available = availableRead()
        let startupFrames = min(capacityFrames, frameCount * 3)
        if !playbackPrimed {
            playbackPrimed = available >= startupFrames
        }
        if !playbackPrimed || available < frameCount {
            playbackPrimed = false
            memset(destination, 0, frameCount * 2 * MemoryLayout<Float>.size)
            return 0
        }
        return read(into: destination, frameCount: frameCount)
    }

    /// Read stereo interleaved frames from the ring buffer. If fewer frames available, pad with silence.
    @discardableResult
    public func read(into destination: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
        let avail = availableRead()
        let toRead = min(frameCount, avail)

        if toRead > 0 {
            let currentRead = Int(readIndex & UInt64(mask))
            let firstPart = min(toRead, capacityFrames - currentRead)
            let secondPart = toRead - firstPart

            memcpy(destination, buffer.advanced(by: currentRead * 2), firstPart * 2 * MemoryLayout<Float>.size)

            if secondPart > 0 {
                memcpy(destination.advanced(by: firstPart * 2), buffer, secondPart * 2 * MemoryLayout<Float>.size)
            }

                readIndex &+= UInt64(toRead)
        }

        // If buffer was short, pad remainder with silence
        if toRead < frameCount {
            let missing = frameCount - toRead
            memset(destination.advanced(by: toRead * 2), 0, missing * 2 * MemoryLayout<Float>.size)
        }

        return toRead
    }
}
