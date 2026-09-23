import AppKit
import SwiftUI

/// Design tokens shared by every screen. Text and status colors use macOS semantic colors, while
/// branded surfaces use one adaptive Light/Dark definition so controls retain their hierarchy.
enum Theme {
    static let background = adaptive(light: 0xFBFBFD, dark: 0x1C1C1E)
    static let sidebarBackground = adaptive(light: 0xF5F5F7, dark: 0x232325)
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

    static let sidebarSelection = adaptive(light: 0xE3ECFA, dark: 0x22324A)
    static let sidebarHover = adaptive(light: 0xEDEDF0, dark: 0x2C2C2E)
    static let favoriteInactive = adaptive(light: 0xC7C7CC, dark: 0x636366)
    static let labelText = adaptive(light: 0x86868B, dark: 0xA1A1A6)
    static let inputBackground = adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let inputBorder = adaptive(light: 0xC7C7CC, dark: 0x545458)
    static let checkboxBorder = adaptive(light: 0x86868B, dark: 0x8E8E93)
    static let inputPlaceholderNSColor = adaptiveNSColor(light: 0x86868B, dark: 0xA1A1A6)
    static let inputPlaceholder = Color(nsColor: inputPlaceholderNSColor)
    static let badgeBackground = adaptive(light: 0xFFFFFF, dark: 0x303033)
    static let badgeBorder = adaptive(light: 0xD1D1D6, dark: 0x545458)
    static let badgeText = adaptive(light: 0x3A3A3C, dark: 0xE5E5EA)
    static let badgeActiveBackground = adaptive(light: 0xEEF4FF, dark: 0x16304F)
    static let badgeActiveBorder = adaptive(light: 0xB9D2F7, dark: 0x2F5A8F)
    static let badgeActiveText = adaptive(light: 0x0A5FCC, dark: 0x64A8FF)
    static let segmentTrack = adaptive(light: 0xE5E5EA, dark: 0x2C2C2E)
    static let segmentSelected = adaptive(light: 0xFFFFFF, dark: 0x5A5A5E)

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

    /// Resolve fixed brand tints through AppKit so windows update immediately when macOS changes
    /// appearance. High-contrast appearances retain the same pairs and receive stronger strokes
    /// at the component level.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: adaptiveNSColor(light: light, dark: dark))
    }

    /// Return the AppKit form of an adaptive color for custom controls that cannot consume a
    /// SwiftUI `Color`, such as the placeholder drawn by `StableInputTextView`.
    static func adaptiveNSColor(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .accessibilityHighContrastDarkAqua,
                .darkAqua,
                .accessibilityHighContrastAqua,
                .aqua,
            ])
            let value = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
                ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
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

extension ToolVisualCategory {
    var iconBackground: Color {
        switch self {
        case .dns: return Theme.adaptive(light: 0xE3EEFB, dark: 0x16304F)
        case .reports: return Theme.adaptive(light: 0xEFE9FB, dark: 0x2E2447)
        case .localNetwork: return Theme.adaptive(light: 0xE2F4EA, dark: 0x173A2A)
        case .routing: return Theme.adaptive(light: 0xFFF0DD, dark: 0x3D2A12)
        case .mail: return Theme.adaptive(light: 0xFCE8EC, dark: 0x44212B)
        case .webAndPorts: return Theme.adaptive(light: 0xE1F3F4, dark: 0x15383A)
        case .utilities: return Theme.adaptive(light: 0xECECF1, dark: 0x343438)
        }
    }

    var iconForeground: Color {
        switch self {
        case .dns: return Theme.adaptive(light: 0x0A5FCC, dark: 0x64A8FF)
        case .reports: return Theme.adaptive(light: 0x6A45C2, dark: 0xB79CFF)
        case .localNetwork: return Theme.adaptive(light: 0x1C8453, dark: 0x4CD68A)
        case .routing: return Theme.adaptive(light: 0xB8620A, dark: 0xFFB340)
        case .mail: return Theme.adaptive(light: 0xB43A55, dark: 0xFF8AA1)
        case .webAndPorts: return Theme.adaptive(light: 0x147A80, dark: 0x5BD6D6)
        case .utilities: return Theme.adaptive(light: 0x56565C, dark: 0xD1D1D6)
        }
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
    var interactive = false
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    private var emphasized: Bool { selected || (interactive && hovering) }

    var body: some View {
        HStack(spacing: 6) {
            Text(localized(text))
                .font(mono ? Theme.mono(compact ? 11 : 12, weight: .medium) : .system(size: compact ? 11 : 12, weight: .medium))
                .foregroundStyle(chipText)
                .lineLimit(1)
            if let secondary {
                Text(localized(secondary))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 5)
        .background(chipBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(chipBorder, lineWidth: contrast == .increased ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering = interactive && $0 }
        .animation(.easeOut(duration: 0.12), value: emphasized)
    }

    private var chipText: Color {
        guard tone == .neutral else { return Theme.color(for: tone) }
        return emphasized ? Theme.badgeActiveText : Theme.badgeText
    }

    private var chipBackground: Color {
        guard tone == .neutral else { return Theme.color(for: tone).opacity(0.1) }
        return emphasized ? Theme.badgeActiveBackground : Theme.badgeBackground
    }

    private var chipBorder: Color {
        guard tone == .neutral else { return Theme.color(for: tone).opacity(0.35) }
        return emphasized ? Theme.badgeActiveBorder : Theme.badgeBorder
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
            .foregroundStyle(Theme.labelText)
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

/// A category-tinted tool tile. The symbol still identifies the tool when color is unavailable.
struct ToolIconTile: View {
    let symbol: String
    var size: CGFloat = 56
    var category: ToolVisualCategory = .dns
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(category.iconForeground)
            .frame(width: size, height: size)
            .background(category.iconBackground, in: shape)
            .overlay(shape.stroke(
                category.iconForeground.opacity(contrast == .increased ? 0.42 : 0.12),
                lineWidth: contrast == .increased ? 1.5 : 1
            ))
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

/// A switch inside a card with a title and one line of explanation.
struct ToggleCard: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 16) {
                SwitchControl(isOn: $isOn)
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized(title)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(localized(subtitle)).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bare)
        .keyboardFocusable()
        .card()
    }
}

/// A unified segmented control with an inset selected segment on a quiet shared track.
struct SegmentedControl: View {
    let options: [String]
    @Binding var selection: Int
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button { selection = index } label: {
                    Text(localized(option))
                        .font(.system(size: 13, weight: selection == index ? .semibold : .medium))
                        .foregroundStyle(selection == index ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(height: Theme.controlHeight - 4)
                        .background(
                            selection == index ? Theme.segmentSelected : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.radius - 2, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: Theme.radius - 2, style: .continuous))
                }
                .buttonStyle(.bare)
                .keyboardFocusable()
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(height: Theme.controlHeight)
        .fixedSize(horizontal: true, vertical: true)
        .background(Theme.segmentTrack)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .stroke(Theme.badgeBorder, lineWidth: contrast == .increased ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// A checkbox in the accent colour for selection lists.
struct CheckMark: View {
    let checked: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            // Keep empty boxes distinct from the surrounding surface in both appearances.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(checked ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.inputBackground))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(checked ? Theme.accentDeep : Theme.checkboxBorder,
                        lineWidth: checked ? 1 : contrast == .increased ? 2 : 1.5)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
            }
        }
        .frame(width: 20, height: 20)
        .animation(.easeOut(duration: 0.12), value: checked)
    }
}

/// A big number with its label, used for the headline figures of a result.
struct StatTile: View {
    let metric: SummaryMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(metric.label)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(localized(metric.value))
                    .font(.system(size: metric.usesCompactValueStyle ? 20 : metric.value.count > 14 ? 15 : metric.value.count > 8 ? 20 : 26,
                                  weight: .semibold, design: .rounded))
                    .foregroundStyle(metric.tone == .neutral ? Theme.textPrimary : Theme.color(for: metric.tone))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .textSelection(.enabled)
                if let unit = metric.unit {
                    Text(localized(unit))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if let detail = metric.detail {
                Text(localized(detail))
                    .font(.system(size: 12.5))
                    .foregroundStyle(metric.tone == .warning || metric.tone == .negative ? Theme.color(for: metric.tone) : Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        // Keep every metric card the same height, including cards without a detail line.
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .topLeading)
        .card(padding: 18)
    }
}

/// Search boxes in the sidebar and above tables.
extension Notification.Name {
    static let focusSidebarSearch = Notification.Name("tools.min.netmin.focus-sidebar-search")
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var trailing: String? = nil
    var compact = false
    var focusOnWindowOpen = false
    var textVerticalOffset: CGFloat = -2
    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            StableTextInput(
                placeholder: localized(placeholder),
                text: $text,
                font: .systemFont(ofSize: compact ? 12.5 : 13),
                contentHeight: compact ? 18 : 20,
                textVerticalOffset: textVerticalOffset,
                focusOnWindowOpen: focusOnWindowOpen,
                handlesSidebarSearchCommand: focusOnWindowOpen,
                onFocusChange: { isFocused = $0 }
            )
            .frame(height: compact ? 18 : 20)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.bare)
                .keyboardFocusable()
                .accessibilityLabel(localized("Clear search"))
            } else if let trailing {
                KeyCap(trailing)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: compact ? 32 : 38)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .stroke(isFocused ? Theme.accent : Theme.border, lineWidth: isFocused ? 1.5 : 1))
        .shadow(color: isFocused ? Theme.accent.opacity(0.25) : .clear, radius: 8)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// A direct single-line text client used everywhere custom field chrome is drawn. AppKit never
/// swaps it for the shared field editor, so text and placeholders keep one baseline across focus.
struct StableTextInput: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let font: NSFont
    let contentHeight: CGFloat
    var textVerticalOffset: CGFloat = -2
    var focusOnWindowOpen = false
    var handlesSidebarSearchCommand = false
    var requestedFocus = false
    var onFocusChange: ((Bool) -> Void)?
    var onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> StableInputScrollView {
        let scrollView = StableInputScrollView(
            font: font,
            contentHeight: contentHeight,
            textVerticalOffset: textVerticalOffset
        )
        let textView = scrollView.textView
        textView.delegate = context.coordinator
        textView.placeholderAttributedString = placeholderText
        textView.focusOnWindowOpen = focusOnWindowOpen
        textView.handlesSidebarSearchCommand = handlesSidebarSearchCommand
        textView.onFocusChange = onFocusChange
        textView.onSubmit = onSubmit
        textView.setAccessibilityRole(.textField)
        textView.setAccessibilityLabel(placeholder)
        return scrollView
    }

    func updateNSView(_ scrollView: StableInputScrollView, context: Context) {
        context.coordinator.text = $text
        let textView = scrollView.textView
        textView.placeholderAttributedString = placeholderText
        textView.focusOnWindowOpen = focusOnWindowOpen
        textView.handlesSidebarSearchCommand = handlesSidebarSearchCommand
        textView.onFocusChange = onFocusChange
        textView.onSubmit = onSubmit
        textView.setAccessibilityLabel(placeholder)
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            textView.needsDisplay = true
        }
        let shouldRequestFocus = requestedFocus && !context.coordinator.lastRequestedFocus
        context.coordinator.lastRequestedFocus = requestedFocus
        if shouldRequestFocus, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async { [weak textView] in
                guard let textView, let window = textView.window else { return }
                _ = window.makeFirstResponder(textView)
            }
        }
    }

    private var placeholderText: NSAttributedString {
        NSAttributedString(
            string: placeholder,
            attributes: [
                .font: font,
                .foregroundColor: Theme.inputPlaceholderNSColor
            ]
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var lastRequestedFocus = false

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let normalized = textView.string.replacingOccurrences(of: "\n", with: " ")
            if normalized != textView.string {
                let selection = textView.selectedRange()
                textView.string = normalized
                textView.setSelectedRange(NSRange(
                    location: min(selection.location, (normalized as NSString).length),
                    length: 0
                ))
            }
            text.wrappedValue = normalized
        }
    }
}

final class StableInputScrollView: NSScrollView {
    let textView = StableInputTextView(frame: .zero)

    init(font: NSFont, contentHeight: CGFloat, textVerticalOffset: CGFloat) {
        super.init(frame: .zero)
        borderType = .noBorder
        drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = false
        automaticallyAdjustsContentInsets = false

        textView.font = font
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.height]
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        // Most field chrome is optically centered two points above the mathematical midpoint.
        textView.textContainerInset = NSSize(
            width: 0,
            height: floor((contentHeight - lineHeight) / 2) + textVerticalOffset
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.maximumNumberOfLines = 1
        textView.textContainer?.lineBreakMode = .byClipping
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false

        textView.minSize = NSSize(width: 0, height: contentHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: contentHeight)
        textView.frame = NSRect(x: 0, y: 0, width: 1, height: contentHeight)
        documentView = textView
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: textView.minSize.height)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class StableInputTextView: NSTextView {
    var placeholderAttributedString: NSAttributedString? {
        didSet { needsDisplay = true }
    }
    var focusOnWindowOpen = false {
        didSet {
            guard focusOnWindowOpen != oldValue else { return }
            configureInitialFocus()
        }
    }
    var handlesSidebarSearchCommand = false {
        didSet {
            guard handlesSidebarSearchCommand != oldValue else { return }
            configureSearchCommand()
        }
    }
    var onFocusChange: ((Bool) -> Void)?
    var onSubmit: (() -> Void)?

    private var keyWindowObserver: NSObjectProtocol?
    private var searchCommandObserver: NSObjectProtocol?
    private var focusScheduled = false
    private var appliedInitialFocus = false

    // Prevent TextInputUI from creating its remote cursor-accessory window. On a cold launch its
    // empty host can otherwise appear briefly as a translucent square beside the insertion point.
    override func preferredTextAccessoryPlacement() -> NSTextCursorAccessoryPlacement { .invisible }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureInitialFocus()
        configureSearchCommand()
    }

    /// The AppKit menu command addresses the key window, so another open Netmin window does not
    /// unexpectedly receive focus. Selecting the current query makes replacement immediate.
    private func configureSearchCommand() {
        removeSearchCommandObserver()
        guard handlesSidebarSearchCommand, let window else { return }
        searchCommandObserver = NotificationCenter.default.addObserver(
            forName: .focusSidebarSearch,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusFromMenuCommand() }
        }
    }

    private func focusFromMenuCommand() {
        guard let window, window.isVisible, window.makeFirstResponder(self) else { return }
        selectAll(nil)
    }

    private func configureInitialFocus() {
        removeKeyWindowObserver()
        guard focusOnWindowOpen, !appliedInitialFocus, let window else { return }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusWhenWindowIsReady() }
        }
        focusWhenWindowIsReady()
    }

    private func focusWhenWindowIsReady() {
        guard !focusScheduled,
              !appliedInitialFocus,
              let window,
              window.isVisible,
              window.isKeyWindow else { return }
        focusScheduled = true
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self else { return }
            self.focusScheduled = false
            guard let window,
                  self.window === window,
                  window.isVisible,
                  window.isKeyWindow else { return }
            if window.makeFirstResponder(self) {
                self.appliedInitialFocus = true
                self.removeKeyWindowObserver()
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 36, 76:
            onSubmit?()
            return
        case 48 where modifiers.isEmpty || modifiers == .shift:
            if modifiers.contains(.shift) {
                window?.selectPreviousKeyView(nil)
            } else {
                window?.selectNextKeyView(nil)
            }
            return
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { reportFocus(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { reportFocus(false) }
        return resigned
    }

    private func reportFocus(_ focused: Bool) {
        guard let onFocusChange else { return }
        DispatchQueue.main.async { onFocusChange(focused) }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholderAttributedString else { return }
        let origin = textContainerOrigin
        placeholderAttributedString.draw(in: NSRect(
            x: origin.x,
            y: origin.y,
            width: max(0, bounds.width - origin.x),
            height: bounds.height - origin.y
        ))
    }

    private func removeKeyWindowObserver() {
        guard let keyWindowObserver else { return }
        NotificationCenter.default.removeObserver(keyWindowObserver)
        self.keyWindowObserver = nil
    }

    private func removeSearchCommandObserver() {
        guard let searchCommandObserver else { return }
        NotificationCenter.default.removeObserver(searchCommandObserver)
        self.searchCommandObserver = nil
    }

    deinit {
        removeKeyWindowObserver()
        removeSearchCommandObserver()
    }
}

/// The main target field. It detects what was typed and shows the matching icon, and turns red
/// with a reason when the value cannot be a valid target.
struct TargetField: View {
    let placeholder: String
    @Binding var text: String
    let kind: TargetKind
    @Binding var isFocused: Bool
    var onSubmit: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous) }
    private var borderColor: Color {
        kind.isInvalid ? Theme.danger.opacity(0.75) : isFocused ? Theme.accent : Theme.inputBorder
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(kind.isInvalid ? Theme.danger : isFocused ? Theme.accent : Theme.inputPlaceholder)
                .frame(width: 18)
                .offset(y: -1.5)
                .contentTransition(.symbolEffect(.replace))
            StableTextInput(
                placeholder: localized(placeholder),
                text: $text,
                font: .monospacedSystemFont(ofSize: 15, weight: .regular),
                contentHeight: 22,
                requestedFocus: isFocused,
                onFocusChange: { isFocused = $0 },
                onSubmit: onSubmit
            )
            .frame(height: 22)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.bare)
                .keyboardFocusable()
                .accessibilityLabel(localized("Clear target"))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Theme.inputBackground, in: shape)
        .overlay(shape.stroke(borderColor, lineWidth: isFocused || kind.isInvalid ? 2 : 1.25))
        .shadow(color: isFocused ? (kind.isInvalid ? Theme.danger : Theme.accent).opacity(0.28) : .clear, radius: 8)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .animation(.easeOut(duration: 0.15), value: kind.isInvalid)
    }
}

/// A thin animated stripe shown while a command runs.
struct ProgressStripe: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.border)
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Theme.accent, Theme.cyan, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * 0.35)
                    .offset(x: (reduceMotion ? 0.3 : phase) * proxy.size.width)
            }
        }
        .frame(height: 2)
        .clipped()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}

// MARK: - Window

/// Extends the semantic window background under the title bar. The system still owns the
/// appearance, controls, and material rendering, including macOS 27's native window treatment.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .automatic
            window.backgroundColor = .windowBackgroundColor
        }
    }
}
