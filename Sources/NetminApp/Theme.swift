import AppKit
import SwiftUI

/// Semantic design tokens shared by every screen. AppKit resolves these colors for the current
/// macOS appearance, contrast setting, and accent color, so custom views stay native in both
/// Light and Dark appearances without maintaining a parallel hard-coded palette.
enum Theme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceRaised = Color(nsColor: .underPageBackgroundColor)
    static let surfaceSunken = Color(nsColor: .textBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let borderStrong = Color(nsColor: .gridColor)
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let accent = Color(nsColor: .controlAccentColor)
    static let onAccent = Color(nsColor: .alternateSelectedControlTextColor)
    static let accentBright = Color(nsColor: .controlAccentColor)
    static let accentDeep = Color(nsColor: .controlAccentColor)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)
    static let cyan = Color(nsColor: .systemTeal)

    static let radius: CGFloat = 10
    static let cardRadius: CGFloat = 12
    static let controlHeight: CGFloat = 34
    static let smallControlHeight: CGFloat = 28

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent.opacity(0.88), accent], startPoint: .top, endPoint: .bottom)
    }

    static var latencyGradient: LinearGradient {
        LinearGradient(colors: [cyan, success], startPoint: .leading, endPoint: .trailing)
    }

    static func mono(_ size: CGFloat = 12.5, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func color(for tone: SummaryTone) -> Color {
        switch tone {
        case .neutral: return textPrimary
        case .accent: return accent
        case .positive: return success
        case .warning: return warning
        case .negative: return danger
        }
    }

    /// Words in status cells that deserve a colour, such as "open" or "timed out".
    static func tone(forStatus text: String) -> SummaryTone {
        let lower = text.lowercased()
        if lower.hasPrefix("open") || lower.hasPrefix("active") || lower.contains("succeeded") || lower == "validated" { return .positive }
        if lower.contains("timed out") || lower.hasPrefix("closed") || lower.contains("no reply") || lower.contains("failed") || lower == "inactive" { return .negative }
        if lower.contains("no answer") || lower.contains("filtered") || lower == "configured" { return .warning }
        return .neutral
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Buttons

enum ButtonVariant { case primary, secondary, ghost, danger, link }
enum ButtonSize { case regular, small }

/// The single button style of the app. Hover lifts the glow and never changes the shape; every
/// shortcut a button owns is printed on it as a chip.
struct NetminButtonStyle: ButtonStyle {
    var variant: ButtonVariant = .secondary
    var size: ButtonSize = .regular
    var shortcut: String? = nil

    func makeBody(configuration: Configuration) -> some View {
        NetminButtonBody(configuration: configuration, variant: variant, size: size, shortcut: shortcut)
    }
}

extension ButtonStyle where Self == NetminButtonStyle {
    static func netmin(_ variant: ButtonVariant = .secondary, size: ButtonSize = .regular, shortcut: String? = nil) -> NetminButtonStyle {
        NetminButtonStyle(variant: variant, size: size, shortcut: shortcut)
    }
}

/// A label-only style for rows, chips, and segments that draw their own states. Unlike the
/// system's plain style it adds no hover capsule, so custom fills keep their exact shape.
struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == BareButtonStyle {
    static var bare: BareButtonStyle { BareButtonStyle() }
}
