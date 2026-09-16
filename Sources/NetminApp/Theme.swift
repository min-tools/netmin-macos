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

/// Opts custom controls into macOS keyboard navigation even when the system preference only tabs
/// between text fields. Buttons keep their native Space and Return activation behavior.
extension View {
    func keyboardFocusable() -> some View {
        focusable(true, interactions: .activate)
    }
}

private struct NetminButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let variant: ButtonVariant
    let size: ButtonSize
    let shortcut: String?
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size == .small ? 8 : Theme.radius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 8) {
            configuration.label
                .lineLimit(1)
            if let shortcut {
                KeyCap(shortcut, style: variant == .primary ? .onAccent : .embedded)
            }
        }
        .font(.system(size: size == .small ? 12 : 13, weight: .semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, variant == .link ? 2 : (size == .small ? 11 : 14))
        .frame(height: size == .small ? Theme.smallControlHeight : Theme.controlHeight)
        .background(AnyShapeStyle(fill), in: shape)
        .overlay(shape.stroke(borderColor, lineWidth: 1))
        .overlay(topHighlight)
        .shadow(color: glowColor, radius: hovering ? 14 : 9, y: 3)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var fill: any ShapeStyle {
        let pressed = configuration.isPressed
        switch variant {
        case .primary:
            if !isEnabled { return Theme.accent.opacity(0.22) }
            return Theme.accentGradient
        case .secondary:
            if !isEnabled { return Theme.surface }
            return pressed ? Theme.surface : hovering ? Theme.textPrimary.opacity(0.10) : Theme.surfaceRaised
        case .ghost:
            return pressed ? Theme.textPrimary.opacity(0.12) : hovering ? Theme.textPrimary.opacity(0.07) : Color.clear
        case .danger:
            return Theme.danger.opacity(pressed ? 0.24 : hovering ? 0.18 : 0.12)
        case .link:
            return Color.clear
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary:
            return Theme.onAccent.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.42)
        case .secondary, .ghost:
            return isEnabled ? Theme.textPrimary.opacity(configuration.isPressed ? 0.8 : 1) : Theme.textTertiary
        case .danger:
            return isEnabled ? Theme.danger : Theme.danger.opacity(0.4)
        case .link:
            return isEnabled ? (hovering ? Theme.accentBright : Theme.accent) : Theme.textTertiary
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary: return isEnabled ? Theme.accentDeep.opacity(0.9) : Color.clear
        case .secondary: return isEnabled ? Theme.borderStrong : Theme.border
        case .ghost, .link: return Color.clear
        case .danger: return Theme.danger.opacity(isEnabled ? 0.45 : 0.2)
        }
    }

    private var glowColor: Color {
        guard isEnabled, variant == .primary else { return .clear }
        return Theme.accent.opacity(hovering ? 0.5 : 0.35)
    }

    /// The 1 px highlight along the top edge that gives controls their lift.
    @ViewBuilder private var topHighlight: some View {
        if variant == .primary || variant == .secondary, isEnabled {
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(variant == .primary ? 0.32 : 0.09), .clear, .clear],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
            .padding(0.5)
        }
    }
}

/// A 34 pt square icon button that lines up with text buttons.
struct IconButton: View {
    let symbol: String
    var help: String
    var variant: ButtonVariant = .secondary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.netmin(variant))
        .keyboardFocusable()
        .frame(width: Theme.controlHeight, height: Theme.controlHeight)
        .help(localized(help))
        .accessibilityLabel(localized(help))
    }
}

/// One entry of a split button's menu; `divider` draws a separator.
struct SplitMenuItem {
    let title: String?
    let action: (() -> Void)?

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    private init() {
        title = nil
        action = nil
    }

    static let divider = SplitMenuItem()
}
