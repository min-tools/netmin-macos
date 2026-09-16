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

/// A primary action with a chevron that opens secondary actions, drawn as one control. Both halves
/// are native keyboard controls, so Tab, Space, Return and menu-arrow navigation work normally.
struct SplitButton: View {
    let title: String
    var shortcut: String?
    /// Forces a segment's hover fill (0 = action, 1 = menu) so previews can show the states.
    var highlightedSegment: Int? = nil
    let action: () -> Void
    let items: [SplitMenuItem]
    @State private var hoveringMain = false
    @State private var hoveringMenu = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous) }
    private var mainLit: Bool { hoveringMain || highlightedSegment == 0 }
    private var menuLit: Bool { hoveringMenu || highlightedSegment == 1 }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Text(localized(title))
                    if let shortcut { KeyCap(shortcut, style: .onAccent) }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14)
                .frame(height: Theme.controlHeight)
                .background(Color.white.opacity(mainLit ? 0.08 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.bare)
            .keyboardFocusable()
            .onHover { hoveringMain = $0 }

            Rectangle().fill(Color.black.opacity(0.28)).frame(width: 1, height: Theme.controlHeight)

            Menu {
                ForEach(items.indices, id: \.self) { index in
                    if let title = items[index].title, let action = items[index].action {
                        Button(localized(title), action: action)
                    } else {
                        Divider()
                    }
                }
            } label: {
                Color.clear
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            // Keep a full square dropdown segment. A borderless Menu otherwise compresses its
            // transparent label and leaves the indicator against the rounded trailing edge.
            .frame(width: Theme.controlHeight, height: Theme.controlHeight)
            .background(Color.white.opacity(menuLit ? 0.08 : 0))
            .contentShape(Rectangle())
            // The borderless AppKit menu can suppress its label tint until first activation.
            // Draw the indicator outside that label so it remains visible in every menu state.
            .overlay {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .allowsHitTesting(false)
            }
            .keyboardFocusable()
            .onHover { hoveringMenu = $0 }
            .accessibilityLabel(localized("More copy options"))
        }
        .background(Theme.accentGradient, in: shape)
        .overlay(shape.stroke(Theme.accentDeep.opacity(0.9), lineWidth: 1))
        .overlay(shape.stroke(LinearGradient(colors: [Color.white.opacity(0.32), .clear, .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1).padding(0.5))
        .clipShape(shape)
        .shadow(color: Theme.accent.opacity(mainLit || menuLit ? 0.5 : 0.35), radius: mainLit || menuLit ? 14 : 9, y: 3)
        .animation(.easeOut(duration: 0.15), value: mainLit || menuLit)
        .fixedSize(horizontal: true, vertical: true)
    }
}

// MARK: - Chips, caps, and pills

/// A keyboard-shortcut cap. Standalone caps explain shortcuts in footers; embedded caps sit inside buttons.
struct KeyCap: View {
    enum Style { case standalone, embedded, onAccent }
    let text: String
    var style: Style = .standalone

    init(_ text: String, style: Style = .standalone) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(localized(text))
            .font(Theme.mono(11, weight: .medium))
            .foregroundStyle(style == .onAccent ? Theme.onAccent.opacity(0.92) : Theme.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                style == .onAccent ? Color.white.opacity(0.16) : style == .embedded ? Theme.surfaceSunken : Theme.surfaceRaised,
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(style == .onAccent ? Color.white.opacity(0.14) : Theme.borderStrong, lineWidth: 1))
    }
}

/// A monospaced value chip, optionally with a lighter secondary label, used for ranges and interfaces.
struct Chip: View {
    let text: String
    var secondary: String? = nil
    var selected = false
    var mono = true
    var tone: SummaryTone = .neutral
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Text(localized(text))
                .font(mono ? Theme.mono(compact ? 11 : 12, weight: .medium) : .system(size: compact ? 11 : 12, weight: .medium))
                .foregroundStyle(tone == .neutral ? Theme.textPrimary : Theme.color(for: tone))
                .lineLimit(1)
            if let secondary {
                Text(localized(secondary))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 5)
        .background(selected ? Theme.accent.opacity(0.14) : tone == .neutral ? Theme.surfaceRaised : Theme.color(for: tone).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(selected ? Theme.accent.opacity(0.7) : tone == .neutral ? Theme.borderStrong : Theme.color(for: tone).opacity(0.35), lineWidth: 1))
    }
}

/// A status dot with a label: Complete, Partial, Failed, or Running.
struct StatusPill: View {
    let tone: SummaryTone
    let text: String
    var pulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.color(for: tone))
                .frame(width: 7, height: 7)
                .shadow(color: Theme.color(for: tone).opacity(0.8), radius: pulsing ? 4 : 2)
                .modifier(PulseModifier(active: pulsing))
            Text(localized(text))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.controlHeight)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
    }
}

private struct PulseModifier: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = false

    func body(content: Content) -> some View {
        content
            .opacity(active && !reduceMotion && !bright ? 0.45 : 1)
            .onAppear {
                guard active, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever()) { bright = true }
            }
    }
}

/// "just now", "2 minutes ago", refreshed every half minute.
struct RelativeTimeText: View {
    let date: Date
    var prefix = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(prefix + RelativeTimeText.describe(date, relativeTo: context.date))
        }
    }

    static func describe(_ date: Date, relativeTo now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return localized("just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// Uppercase, tracked labels that head a group of controls or a card.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(localized(text).uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat
    var sunken: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(sunken ? Theme.surfaceSunken : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 0, sunken: Bool = false) -> some View {
        modifier(CardModifier(padding: padding, sunken: sunken))
    }

    /// Row hover highlight for lists and tables.
    func hoverHighlight(cornerRadius: CGFloat = 8) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}

private struct HoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(Theme.textPrimary.opacity(hovering ? 0.055 : 0), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering = $0 }
    }
}

/// The gradient tile that identifies a tool, with a soft glow at larger sizes.
struct ToolIconTile: View {
    let symbol: String
    var size: CGFloat = 56

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: size, height: size)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: Theme.accent.opacity(size >= 48 ? 0.45 : 0.25), radius: size * 0.32, y: size * 0.12)
    }
}

// MARK: - Controls

/// A capsule switch in the accent colour.
struct SwitchControl: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.borderStrong))
                Circle()
                    .fill(.white)
                    .padding(3)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .frame(width: 44, height: 24)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
        }
        .buttonStyle(.bare)
        .keyboardFocusable()
        .accessibilityValue(localized(isOn ? "On" : "Off"))
    }
}
