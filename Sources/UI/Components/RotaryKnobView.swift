import SwiftUI

/// Vintage Console Rotary Knob with Value Drag and Double-click Reset
public struct RotaryKnobView: View {
    public let title: String
    @Binding public var value: Float
    public let range: ClosedRange<Float>
    public let defaultValue: Float
    public let unit: String
    public let isDB: Bool
    public let isLogarithmic: Bool

    @State private var dragStartY: CGFloat = 0
    @State private var valueStart: Float = 0

    public init(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        defaultValue: Float = 0.0,
        unit: String = "",
        isDB: Bool = false,
        isLogarithmic: Bool = false
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.defaultValue = defaultValue
        self.unit = unit
        self.isDB = isDB
        self.isLogarithmic = isLogarithmic
    }

    private var normalizedValue: Float {
        if isLogarithmic {
            let logMin = log10(max(1.0, range.lowerBound))
            let logMax = log10(max(1.0, range.upperBound))
            let logVal = log10(max(range.lowerBound, value))
            let span = logMax - logMin
            return span > 0 ? (logVal - logMin) / span : 0.5
        } else {
            let span = range.upperBound - range.lowerBound
            if span <= 0 { return 0.5 }
            return (value - range.lowerBound) / span
        }
    }

    private var rotationAngle: Angle {
        // -135 deg to +135 deg
        let norm = normalizedValue
        let degrees = -135.0 + Double(norm) * 270.0
        return .degrees(degrees)
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(VMTheme.fontLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(VMTheme.textSecondary)

            // Knob Circle
            ZStack {
                // Outer ring track
                Circle()
                    .stroke(VMTheme.panelBorder, lineWidth: 2)
                    .frame(width: 32, height: 32)

                // Knob Body
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [VMTheme.stripBgTop, VMTheme.stripBgBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .shadow(color: Color.black.opacity(0.8), radius: 2)

                // Indicator Pointer Line
                Rectangle()
                    .fill(value != defaultValue ? VMTheme.textAccent : VMTheme.textSecondary)
                    .frame(width: 2, height: 8)
                    .offset(y: -8)
                    .rotationEffect(rotationAngle)
            }
            .contentShape(Circle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    self.value = defaultValue
                }
            )
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        if dragStartY == 0 {
                            dragStartY = gesture.startLocation.y
                            valueStart = value
                        }
                        let deltaY = Float(dragStartY - gesture.location.y)
                        if isLogarithmic {
                            let logMin = log10f(max(1.0, range.lowerBound))
                            let logMax = log10f(max(1.0, range.upperBound))
                            let logSpan = logMax - logMin
                            let logStart = log10f(max(range.lowerBound, valueStart))
                            let deltaNorm = deltaY / 150.0
                            let newLog = logStart + deltaNorm * logSpan
                            let newVal = powf(10.0, max(logMin, min(logMax, newLog)))
                            if newVal < 100 {
                                self.value = round(newVal * 10.0) / 10.0
                            } else if newVal < 1000 {
                                self.value = round(newVal)
                            } else {
                                self.value = round(newVal / 10.0) * 10.0
                            }
                        } else {
                            let span = range.upperBound - range.lowerBound
                            let step = span / 100.0
                            let newVal = valueStart + deltaY * step
                            self.value = max(range.lowerBound, min(range.upperBound, round(newVal * 10.0) / 10.0))
                        }
                    }
                    .onEnded { _ in
                        dragStartY = 0
                    }
            )

            // Numeric Value readout (double click to reset)
            Text(formattedValue)
                .font(VMTheme.fontSmall)
                .foregroundColor(value != defaultValue ? VMTheme.textAccent : VMTheme.textPrimary)
                .frame(width: 48, height: 12)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    self.value = defaultValue
                }
        }
    }

    private var formattedValue: String {
        if isDB {
            return String(format: "%+.1fdB", value)
        } else if unit == "Hz" {
            if value >= 10000 {
                return String(format: "%.1fk", value / 1000.0)
            } else if value >= 1000 {
                return String(format: "%.2fk", value / 1000.0)
            } else {
                return String(format: "%.0fHz", value)
            }
        } else if unit.isEmpty {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.1f%@", value, unit)
        }
    }
}
