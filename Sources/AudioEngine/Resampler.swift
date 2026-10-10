import Foundation

/// Real-time sample rate converter with Adaptive Clock Drift Compensation (PID / EMA Controller)
public final class AdaptiveResampler {
    private var sourceSampleRate: Double
    private var targetSampleRate: Double
    private var nominalRatio: Double

    // Adaptive drift tracking state
    private var smoothedFillLevel: Float = 0.5
    private let targetFillLevel: Float
    private let kp: Double = 0.02  // Proportional gain
    private let ki: Double = 0.000002 // Integral gain
    private var integralError: Double = 0.0
    private var currentRatio: Double
    private var outputFrameRemainder: Double = 0.0
    private var inputFrameRemainder: Double = 0.0
    private var sourcePosition: Double = 0
    private let history = UnsafeMutablePointer<Float>.allocate(capacity: 8)

    public init(sourceRate: Double, targetRate: Double, targetFill: Float = 0.5) {
        self.targetFillLevel = targetFill
        self.smoothedFillLevel = targetFill
        self.sourceSampleRate = max(sourceRate, 8000.0)
        self.targetSampleRate = max(targetRate, 8000.0)
        self.nominalRatio = self.targetSampleRate / self.sourceSampleRate
        self.currentRatio = self.nominalRatio
        history.initialize(repeating: 0, count: 8)

    }

    deinit { history.deallocate() }

    public func updateRates(sourceRate: Double, targetRate: Double) {
        if abs(sourceSampleRate - sourceRate) > 1.0 || abs(targetSampleRate - targetRate) > 1.0 {
            sourceSampleRate = max(sourceRate, 8000.0)
            targetSampleRate = max(targetRate, 8000.0)
            nominalRatio = targetSampleRate / sourceSampleRate
            currentRatio = nominalRatio
            integralError = 0.0
            smoothedFillLevel = targetFillLevel
            outputFrameRemainder = 0.0
            inputFrameRemainder = 0.0
            sourcePosition = 0
            history.update(repeating: 0, count: 8)
        }
    }

    /// Update drift tracking controller based on ring buffer fill level (0.0 to 1.0)
    public func updateDrift(currentFillRatio: Float) {
        // Low-pass filter for smoothed fill level
        let alpha: Float = 0.02
        smoothedFillLevel = smoothedFillLevel * (1.0 - alpha) + currentFillRatio * alpha

        let error = Double(smoothedFillLevel - targetFillLevel) / Double(max(0.001, targetFillLevel))
        integralError += error
        integralError = max(-2500.0, min(2500.0, integralError)) // anti-windup

        // A fuller producer ring must produce fewer frames (and a fuller consumer
        // ring must consume more frames), hence the subtraction here.
        let correction = (kp * error) + (ki * integralError)
        let clampedCorrection = max(-0.005, min(0.005, correction))
        currentRatio = nominalRatio * (1.0 - clampedCorrection)
    }

    /// Number of target-clock frames to produce for a source-clock block.
    /// The fractional carry is essential for small clock corrections: without it,
    /// rounding a 256-frame block makes sub-0.4% corrections disappear entirely.
    public func outputFrameCount(forSourceFrames sourceFrames: Int) -> Int {
        guard sourceFrames > 0 else { return 0 }
        let exact = Double(sourceFrames) * currentRatio + outputFrameRemainder
        let frames = max(1, Int(exact.rounded(.down)))
        outputFrameRemainder = exact - Double(frames)
        return frames
    }

    /// Number of source-clock frames needed to render a target-clock block.
    public func inputFrameCount(forTargetFrames targetFrames: Int) -> Int {
        guard targetFrames > 0 else { return 0 }
        let exact = Double(targetFrames) / currentRatio + inputFrameRemainder
        let frames = max(1, Int(exact.rounded(.down)))
        inputFrameRemainder = exact - Double(frames)
        return frames
    }

    /// Resample stereo interleaved samples from input to output using high-precision fractional cubic Hermite interpolation
    /// This allows continuously variable micro-ratio without allocating a converter!
    @discardableResult
    public func resample(
        source: UnsafePointer<Float>,
        sourceFrames: Int,
        destination: UnsafeMutablePointer<Float>,
        targetFrames: Int
    ) -> Int {
        if sourceFrames <= 0 || targetFrames <= 0 { return 0 }

        // Keep phase and the preceding samples across callbacks. A two-frame
        // causal delay supplies the Hermite lookahead without boundary clamping.
        let step = 1.0 / currentRatio
        func sample(_ frame: Int, _ channel: Int) -> Float {
            if frame < 0 { return history[max(0, min(3, frame + 4)) * 2 + channel] }
            return source[min(sourceFrames - 1, frame) * 2 + channel]
        }
        for i in 0..<targetFrames {
            let position = sourcePosition - 2
            let index = Int(floor(position))
            let fraction = Float(position - Double(index))
            for channel in 0..<2 {
                let y0 = sample(index - 1, channel)
                let y1 = sample(index, channel)
                let y2 = sample(index + 1, channel)
                let y3 = sample(index + 2, channel)
                let c1 = 0.5 * (y2 - y0)
                let c2 = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
                let c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
                destination[i * 2 + channel] = ((c3 * fraction + c2) * fraction + c1) * fraction + y1
            }
            sourcePosition += step
        }
        sourcePosition -= Double(sourceFrames)
        // Copy forward so a source block shorter than four frames also works.
        for frame in 0..<4 {
            for channel in 0..<2 { history[frame * 2 + channel] = sample(sourceFrames - 4 + frame, channel) }
        }
        return targetFrames
    }
}
