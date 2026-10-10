// Run: ./Tests/run_audio_tests.sh
import Foundation

@main
struct PlaybackBufferTests {
    static func main() {
        let ring = StereoRingBuffer(capacityFrames: 2048)
        let block = 128
        let source = UnsafeMutablePointer<Float>.allocate(capacity: 512 * 2)
        let output = UnsafeMutablePointer<Float>.allocate(capacity: block * 2)
        defer { source.deallocate(); output.deallocate() }
        source.initialize(repeating: 0.25, count: 512 * 2)
        output.initialize(repeating: 1, count: block * 2)
        ring.write(from: source, frameCount: block)
        assert(ring.readForPlayback(into: output, frameCount: block) == 0)
        assert(ring.availableRead() == block)
        assert(output[0] == 0)
        ring.write(from: source, frameCount: block * 2)
        assert(ring.readForPlayback(into: output, frameCount: block) == block)
        assert(output[0] == 0.25)
        // Alternating callback order: a cycle with no producer, then two blocks.
        for _ in 0..<1000 {
            assert(ring.readForPlayback(into: output, frameCount: block) == block)
            ring.write(from: source, frameCount: block * 2)
            assert(ring.readForPlayback(into: output, frameCount: block) == block)
        }
        // A real interruption must re-prime without consuming partial data.
        _ = ring.readForPlayback(into: output, frameCount: block)
        _ = ring.readForPlayback(into: output, frameCount: block)
        ring.write(from: source, frameCount: 32)
        assert(ring.readForPlayback(into: output, frameCount: block) == 0)
        assert(ring.availableRead() == 32)
        ring.write(from: source, frameCount: block * 3 - 32)
        assert(ring.readForPlayback(into: output, frameCount: block) == block)
        ring.reset()
        ring.write(from: source, frameCount: block)
        assert(ring.readForPlayback(into: output, frameCount: block) == 0)
        // Ordinary reads (recorder) retain their original immediate behavior.
        assert(ring.read(into: output, frameCount: block) == block)
        print("Playback buffer tests passed")
    }
}
