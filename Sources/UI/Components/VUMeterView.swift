import SwiftUI

struct LiveVUMeterView: View {
    @ObservedObject var meters: MixerMeterStore
    let target: InsertTarget
    let height: CGFloat
    var body: some View { VUMeterView(level: meters.level(target), height: height) }
}

/// Stereo VU Meter Bar with Peak Hold and Tri-color LED Gradient
public struct VUMeterView: View {
    public let level: MeterLevel
    public let height: CGFloat

    public init(level: MeterLevel, height: CGFloat = 180) {
        self.level = level
        self.height = height
    }

    private func dbToNormalized(_ db: Float) -> CGFloat {
        if db <= -60.0 { return 0.0 }
        if db >= 6.0 { return 1.0 }
        // Non-linear visual curve: expand top range (-20 to 0dB) for visual readability
        let clamped = max(-60.0, min(6.0, db))
        let norm = CGFloat((clamped + 60.0) / 66.0)
        return pow(norm, 1.4)
    }

    public var body: some View {
        HStack(spacing: 2) {
            // Left Channel
            meterBar(rmsDB: level.leftRMSDB, peakDB: level.leftPeakDB)
            // Right Channel
            meterBar(rmsDB: level.rightRMSDB, peakDB: level.rightPeakDB)
        }
        .padding(2)
        .background(VMTheme.vuBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(VMTheme.panelBorder.opacity(0.8), lineWidth: 1)
        )
        .frame(width: 14, height: height)
    }

    @ViewBuilder
    private func meterBar(rmsDB: Float, peakDB: Float) -> some View {
        let rmsNorm = dbToNormalized(rmsDB)
        let peakNorm = dbToNormalized(peakDB)

        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background dark track
                Rectangle()
                    .fill(Color.black.opacity(0.6))

                // Active level gradient
                Rectangle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: VMTheme.vuGreen, location: 0.0),
                                .init(color: VMTheme.vuGreen, location: 0.65),
                                .init(color: VMTheme.vuYellow, location: 0.85),
                                .init(color: VMTheme.vuRed, location: 0.95),
                                .init(color: VMTheme.vuRed, location: 1.0)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: max(0, geo.size.height * rmsNorm))

                // Peak Hold Line
                if peakNorm > 0.02 {
                    Rectangle()
                        .fill(peakDB > -0.5 ? VMTheme.vuRed : VMTheme.vuPeakHold)
                        .frame(height: 2)
                        .offset(y: -max(0, geo.size.height * peakNorm - 2))
                }
            }
        }
    }
}
