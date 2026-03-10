import SwiftUI

enum FoxTheme {
    static let backgroundTop = Color(red: 0.95, green: 0.73, blue: 0.43)
    static let backgroundBottom = Color(red: 0.16, green: 0.12, blue: 0.10)
    static let homeStageTop = Color(red: 0.11, green: 0.56, blue: 0.88)
    static let homeStageBottom = Color(red: 0.14, green: 0.22, blue: 0.34)
    static let accent = Color(red: 1.00, green: 0.53, blue: 0.24)
    static let accentSoft = Color(red: 1.00, green: 0.88, blue: 0.70)
    static let glassStroke = Color.white.opacity(0.18)
    static let historyDot = Color(red: 1.00, green: 0.24, blue: 0.30)
    static let readyGreen = Color(red: 0.28, green: 0.82, blue: 0.52)
    static let modalBackdrop = Color.black.opacity(0.34)
    static let pageGradient = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )
    static let settingsBackground = LinearGradient(
        colors: [
            Color(red: 0.17, green: 0.42, blue: 0.70).opacity(0.96),
            Color(red: 0.56, green: 0.41, blue: 0.28).opacity(0.76),
            Color(red: 0.12, green: 0.10, blue: 0.14).opacity(0.92)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let homeStageGradient = LinearGradient(
        colors: [homeStageTop, homeStageBottom],
        startPoint: .top,
        endPoint: .bottom
    )
    static let historyBackground = LinearGradient(
        colors: [
            Color(red: 0.14, green: 0.32, blue: 0.55).opacity(0.98),
            Color(red: 0.53, green: 0.38, blue: 0.24).opacity(0.78),
            Color(red: 0.11, green: 0.09, blue: 0.14).opacity(0.95)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let glassCard = RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(.ultraThinMaterial)
    static let topFade = LinearGradient(
        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04), .clear],
        startPoint: .top,
        endPoint: .bottom
    )
    static let bottomFade = LinearGradient(
        colors: [.clear, Color.white.opacity(0.03), Color.white.opacity(0.09)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let homeTopMask = LinearGradient(
        colors: [Color.white.opacity(0.12), Color.white.opacity(0.03), .clear],
        startPoint: .top,
        endPoint: .bottom
    )
    static let homeBottomMask = LinearGradient(
        colors: [.clear, Color.white.opacity(0.02), Color.white.opacity(0.12)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let homeTopGlow = RadialGradient(
        colors: [Color.white.opacity(0.18), homeStageTop.opacity(0.12), .clear],
        center: .center,
        startRadius: 0,
        endRadius: 230
    )
    static let homeBottomGlow = RadialGradient(
        colors: [accent.opacity(0.18), homeStageBottom.opacity(0.14), .clear],
        center: .center,
        startRadius: 0,
        endRadius: 260
    )
    static let homeGlassMistTop = LinearGradient(
        colors: [Color.white.opacity(0.14), Color.white.opacity(0.04), .clear],
        startPoint: .top,
        endPoint: .bottom
    )
    static let homeGlassMistBottom = LinearGradient(
        colors: [.clear, Color.white.opacity(0.03), Color.white.opacity(0.1)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let homeTopPanelStroke = Color.white.opacity(0.12)
    static let homeBottomPanelStroke = Color.white.opacity(0.1)
}
