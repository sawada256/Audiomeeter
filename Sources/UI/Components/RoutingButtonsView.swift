import SwiftUI

/// Glowing LED Button for Audiomeeter Routing & Mute/Solo
public struct LEDButton: View {
    public let label: String
    public let isActive: Bool
    public let activeColor: Color
    public let action: () -> Void

    public init(label: String, isActive: Bool, activeColor: Color, action: @escaping () -> Void) {
        self.label = label
        self.isActive = isActive
        self.activeColor = activeColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(isActive ? activeColor.opacity(0.25) : VMTheme.ledInactive)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(isActive ? activeColor : VMTheme.panelBorder.opacity(0.6), lineWidth: 1)
                    )

                if isActive {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(activeColor.opacity(0.5), lineWidth: 2)
                        .blur(radius: 2)
                }

                Text(label)
                    .font(VMTheme.fontDigit)
                    .foregroundColor(isActive ? activeColor : VMTheme.ledInactiveText)
                    .shadow(color: isActive ? activeColor.opacity(0.8) : .clear, radius: isActive ? 3 : 0)
            }
            .frame(height: 20)
        }
        .buttonStyle(.plain)
    }
}

/// Routing Matrix Block: [A1] [A2] [A3] / [B1] [B2]
public struct RoutingButtonsView: View {
    public let routing: RoutingMatrix
    public let onToggle: (BusID) -> Void

    public init(routing: RoutingMatrix, onToggle: @escaping (BusID) -> Void) {
        self.routing = routing
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(spacing: 4) {
            // A1, A2, A3
            HStack(spacing: 3) {
                LEDButton(label: "A1", isActive: routing.a1, activeColor: VMTheme.ledAActive) {
                    onToggle(.A1)
                }
                LEDButton(label: "A2", isActive: routing.a2, activeColor: VMTheme.ledAActive) {
                    onToggle(.A2)
                }
                LEDButton(label: "A3", isActive: routing.a3, activeColor: VMTheme.ledAActive) {
                    onToggle(.A3)
                }
            }

            // B1, B2
            HStack(spacing: 3) {
                LEDButton(label: "B1", isActive: routing.b1, activeColor: VMTheme.ledBActive) {
                    onToggle(.B1)
                }
                LEDButton(label: "B2", isActive: routing.b2, activeColor: VMTheme.ledBActive) {
                    onToggle(.B2)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Mute & Solo Buttons
public struct MuteSoloView: View {
    public let isMuted: Bool
    public let isSolo: Bool
    public let onToggleMute: () -> Void
    public let onToggleSolo: () -> Void

    public init(isMuted: Bool, isSolo: Bool, onToggleMute: @escaping () -> Void, onToggleSolo: @escaping () -> Void) {
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.onToggleMute = onToggleMute
        self.onToggleSolo = onToggleSolo
    }

    public var body: some View {
        HStack(spacing: 3) {
            LEDButton(label: L10n.text("Mute"), isActive: isMuted, activeColor: VMTheme.ledMuteActive) {
                onToggleMute()
            }
            LEDButton(label: L10n.text("Solo"), isActive: isSolo, activeColor: VMTheme.ledSoloActive) {
                onToggleSolo()
            }
        }
        .padding(.horizontal, 4)
    }
}
