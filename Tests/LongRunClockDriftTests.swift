// Run: ./Tests/run_audio_tests.sh
import Foundation

@main
struct LongRunClockDriftTests {
    static func main() {
        runInputClockSimulation(relativeClockRate: 1.0001, hours: 3)
        runInputClockSimulation(relativeClockRate: 0.9999, hours: 3)
        for rate in [1.0001, 0.9999] {
            for output in [false, true] {
                for block in [32, 256, 512, 4096] {
                    let fill = min(output ? Float(0.65) : Float(0.45), Float(block * 3) / 16384)
                    runInputClockSimulation(relativeClockRate: rate, hours: block == 32 || block == 4096 ? 1 : 3, block: block, targetFill: fill, output: output)
                }
            }
        }
        print("Long-run clock drift tests passed (legacy and 32/256/512/4096-frame low-latency targets)")
    }

    private static func runInputClockSimulation(relativeClockRate: Double, hours: Double, block: Int = 256, targetFill: Float = 0.5, output: Bool = false) {
        let sampleRate = 48_000.0
        let ring = StereoRingBuffer(capacityFrames: 16_384)
        let resampler = AdaptiveResampler(sourceRate: sampleRate, targetRate: sampleRate, targetFill: targetFill)
        let sourceCapacity = Int(ceil(Double(block) * 1.005)) + 8
        let source = UnsafeMutablePointer<Float>.allocate(capacity: sourceCapacity * 2)
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: (block + 32) * 2)
        defer { source.deallocate(); samples.deallocate() }
        source.initialize(repeating: 0.25, count: sourceCapacity * 2)

        let producerPeriod = Double(block) / (sampleRate * relativeClockRate)
        let consumerPeriod = Double(block) / sampleRate
        let endTime = hours * 3_600
        var producerTime = 0.0
        var consumerTime = 0.0
        var primed = false
        var postPrimeUnderflows = 0
        var overflows = 0
        var producerCallbacks = 0

        while min(producerTime, consumerTime) < endTime {
            if producerTime <= consumerTime {
                if !output { resampler.updateDrift(currentFillRatio: ring.fillRatio()) }
                let frames = output ? block : resampler.outputFrameCount(forSourceFrames: block)
                let written = ring.write(from: source, frameCount: frames)
                if written != frames { overflows += 1 }
                producerCallbacks += 1
                // Deterministic scheduling jitter without changing average rate.
                let jitter = producerCallbacks % 2 == 0 ? 0.000_002 : -0.000_002
                producerTime += producerPeriod + jitter
            } else {
                if output { resampler.updateDrift(currentFillRatio: ring.fillRatio()) }
                let needed = output ? resampler.inputFrameCount(forTargetFrames: block) : block
                let read = ring.readForPlayback(into: samples, frameCount: needed)
                if read > 0 { primed = true }
                if primed && read == 0 { postPrimeUnderflows += 1 }
                consumerTime += consumerPeriod
            }
        }

        print("output=\(output) clock=\(relativeClockRate) block=\(block) fill=\(targetFill) underflows=\(postPrimeUnderflows) overflows=\(overflows)")
        fflush(stdout)
        precondition(postPrimeUnderflows == 0, "underflow at clock rate \(relativeClockRate), block \(block), fill \(targetFill)")
        precondition(overflows == 0, "overflow at clock rate \(relativeClockRate), block \(block), fill \(targetFill)")
    }
}
