import SwiftUI

/// 2D Voice Color / Spatial Pan XY Trackpad
public struct IntellipanPadView: View {
    @Binding public var state: IntellipanState
    public let size: CGFloat

    public init(state: Binding<IntellipanState>, size: CGFloat = 88) {
        self._state = state
        self.size = size
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text("INTELLIPAN")
                .font(VMTheme.fontLabel)
                .foregroundColor(VMTheme.textSecondary)

            GeometryReader { geo in
                let halfW = geo.size.width / 2
                let halfH = geo.size.height / 2
                let puckX = halfW + CGFloat(state.x) * (halfW - 8)
                let puckY = halfH - CGFloat(state.y) * (halfH - 8)

                ZStack {
                    // Pad Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(VMTheme.panelBorder, lineWidth: 1)
                        )

                    // Grid Crosshairs
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: halfH))
                        path.addLine(to: CGPoint(x: geo.size.width, y: halfH))
                        path.move(to: CGPoint(x: halfW, y: 0))
                        path.addLine(to: CGPoint(x: halfW, y: geo.size.height))
                    }
                    .stroke(VMTheme.panelBorder.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))

                    // Text Guides
                    VStack {
                        Text("Bright").font(VMTheme.fontSmall).foregroundColor(VMTheme.textSecondary.opacity(0.6))
                        Spacer()
                        Text("Dark").font(VMTheme.fontSmall).foregroundColor(VMTheme.textSecondary.opacity(0.6))
                    }
                    .padding(2)

                    // Movable Puck
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [VMTheme.textAccent, VMTheme.textAccent.opacity(0.4)],
                                center: .center,
                                startRadius: 1,
                                endRadius: 6
                            )
                        )
                        .frame(width: 14, height: 14)
                        .shadow(color: VMTheme.textAccent, radius: 4)
                        .position(x: puckX, y: puckY)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        self.state = IntellipanState(x: 0.0, y: 0.0)
                    }
                )
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let clampedX = max(8, min(geo.size.width - 8, value.location.x))
                            let clampedY = max(8, min(geo.size.height - 8, value.location.y))
                            let normX = Float((clampedX - halfW) / (halfW - 8))
                            let normY = Float((halfH - clampedY) / (halfH - 8))
                            self.state = IntellipanState(x: normX, y: normY)
                        }
                )
            }
            .frame(width: size, height: size)
        }
    }
}
