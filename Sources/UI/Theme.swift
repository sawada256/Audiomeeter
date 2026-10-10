import SwiftUI

/// Voicemeeter Banana Color Palette and Styling Tokens
public enum VMTheme {
    // Console Backgrounds
    public static let consoleBg = Color(red: 0.08, green: 0.09, blue: 0.11)       // #14171c
    public static let stripBgTop = Color(red: 0.13, green: 0.15, blue: 0.18)      // #21262e
    public static let stripBgBottom = Color(red: 0.09, green: 0.10, blue: 0.12)   // #171a1f
    public static let panelBorder = Color(red: 0.22, green: 0.25, blue: 0.30)     // #38404d
    public static let grooveDark = Color(red: 0.04, green: 0.05, blue: 0.06)      // #0a0d10

    // Strip Header Backgrounds
    public static let hwHeaderBg = Color(red: 0.11, green: 0.18, blue: 0.24)      // Slate blue
    public static let virtualHeaderBg = Color(red: 0.18, green: 0.14, blue: 0.24) // Deep purple/violet
    public static let masterHeaderBg = Color(red: 0.22, green: 0.16, blue: 0.12)  // Deep amber/bronze

    // LED Button Colors
    public static let ledAActive = Color(red: 0.10, green: 0.88, blue: 0.48)      // Vibrant Green A1-A3
    public static let ledBActive = Color(red: 1.00, green: 0.62, blue: 0.10)      // Amber Orange B1-B2
    public static let ledMuteActive = Color(red: 1.00, green: 0.22, blue: 0.28)   // Red Mute
    public static let ledSoloActive = Color(red: 1.00, green: 0.85, blue: 0.15)   // Yellow Solo
    public static let ledInactive = Color(red: 0.18, green: 0.20, blue: 0.24)     // Off State Button
    public static let ledInactiveText = Color(red: 0.45, green: 0.48, blue: 0.54) // Off State Text

    // Fader & Accents
    public static let faderTrack = Color(red: 0.05, green: 0.06, blue: 0.07)
    public static let faderCapTop = Color(red: 0.28, green: 0.32, blue: 0.38)
    public static let faderCapBottom = Color(red: 0.14, green: 0.16, blue: 0.20)
    public static let faderCyanLine = Color(red: 0.00, green: 0.82, blue: 1.00)

    // VU Meter Colors
    public static let vuGreen = Color(red: 0.12, green: 0.90, blue: 0.38)
    public static let vuYellow = Color(red: 1.00, green: 0.85, blue: 0.10)
    public static let vuRed = Color(red: 1.00, green: 0.25, blue: 0.25)
    public static let vuPeakHold = Color(red: 1.00, green: 1.00, blue: 1.00)
    public static let vuBackground = Color(red: 0.05, green: 0.06, blue: 0.08)

    // Text Colors
    public static let textPrimary = Color(red: 0.92, green: 0.94, blue: 0.96)
    public static let textSecondary = Color(red: 0.58, green: 0.62, blue: 0.68)
    public static let textAccent = Color(red: 0.00, green: 0.82, blue: 1.00)
    public static let textGold = Color(red: 1.00, green: 0.78, blue: 0.25)
    public static let panelBackground = Color(red: 0.13, green: 0.15, blue: 0.18)
    public static let panelBackgroundDark = Color(red: 0.09, green: 0.10, blue: 0.12)
    public static let backgroundDark = Color(red: 0.08, green: 0.09, blue: 0.11)
    public static let accentGreen = Color(red: 0.10, green: 0.88, blue: 0.48)
    public static let btnA = Color(red: 0.10, green: 0.88, blue: 0.48)
    public static let btnB = Color(red: 1.00, green: 0.62, blue: 0.10)

    // Typography
    public static let fontTitle = Font.system(size: 11, weight: .bold, design: .monospaced)
    public static let fontSection = Font.system(size: 10, weight: .bold, design: .monospaced)
    public static let fontLabel = Font.system(size: 9, weight: .semibold, design: .default)
    public static let fontSmall = Font.system(size: 8, weight: .medium, design: .monospaced)
    public static let fontSmallBold = Font.system(size: 9, weight: .bold, design: .default)
    public static let fontDigit = Font.system(size: 10, weight: .bold, design: .monospaced)
}

public enum MixerLayout {
    public static let stripHeight: CGFloat = 520
    public static let controlsHeight: CGFloat = 164
    public static let faderHeight: CGFloat = 170
}
