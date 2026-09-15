import AppKit
import SwiftUI

/// The Local Device Sweep form: the networks this Mac can see, each with an estimate, plus a
/// field for adding ranges by hand.
struct SweepFormView: View {
    @ObservedObject var model: AppModel
    @State private var rangeError: String?
    @State private var rangeFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Networks to scan")
                Spacer()
                Text(detectedText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            if model.sweepRanges.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.sweepRanges.enumerated()), id: \.element.id) { index, range in
                        if index > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                        RangeRow(range: range, toggle: { model.toggleRange(range.id) },
                                 remove: range.isCustom ? { model.removeRange(range.id) } : nil)
                    }
                }
                .card()
            }
            addRangeField
            if let rangeError {
                Text(localized(rangeError))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    private var detectedText: String {
        let detected = model.sweepRanges.filter { !$0.isCustom }.count
        guard detected > 0 else { return localized("Nothing detected") }
        let total = 4 + model.sweepRanges.reduce(0) { $0 + $1.estimatedSeconds }
        return localizedFormat("%lld detected · scanning all takes about %lld s", Int64(detected), Int64(total))
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("No private IPv4 network was detected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Join a network or add a range below. Running the sweep asks the helper to look again.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Detect again") { model.refreshSweepRanges() }
                .buttonStyle(.netmin(.secondary, size: .small))
                .keyboardFocusable()
        }
        .card(padding: 18)
    }

    private var addRangeField: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        return HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(rangeFocused ? Theme.accent : Theme.textTertiary)
                .frame(width: 18)
            StableTextInput(
                placeholder: localized("Add a range, e.g. 172.16.4.0/22"),
                text: $model.rangeDraft,
                font: .monospacedSystemFont(ofSize: 14, weight: .regular),
                contentHeight: 21,
                requestedFocus: rangeFocused,
                onFocusChange: { rangeFocused = $0 },
                onSubmit: addRange
            )
            .frame(height: 21)
            if !model.rangeDraft.isEmpty {
                Button("Add", action: addRange)
                    .buttonStyle(.netmin(.secondary, size: .small, shortcut: "↩"))
                    .keyboardFocusable()
            } else if let recent = model.recentRange {
                HStack(spacing: 8) {
                    Text("Recent").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    Button { rangeError = model.addRange(recent) } label: { Chip(text: recent) }
                        .buttonStyle(.bare)
                        .keyboardFocusable()
                        .help(localizedFormat("Add %@ to the scan", recent))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.surfaceSunken, in: shape)
        .overlay(shape.stroke(rangeError != nil ? Theme.danger.opacity(0.7) : rangeFocused ? Theme.accent : Theme.border,
                              lineWidth: rangeFocused ? 1.5 : 1))
        .shadow(color: rangeFocused ? Theme.accent.opacity(0.25) : .clear, radius: 8)
        .animation(.easeOut(duration: 0.15), value: rangeFocused)
        .onChange(of: model.rangeDraft) { _, _ in rangeError = nil }
    }

    private func addRange() {
        rangeError = model.addRange()
    }
}

private struct RangeRow: View {
    let range: SweepRange
    let toggle: () -> Void
    let remove: (() -> Void)?

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                CheckMark(checked: range.isSelected)
                Text(range.cidr)
                    .font(Theme.mono(14, weight: .medium))
                    .foregroundStyle(range.isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 180, alignment: .leading)
                Text(localized(interfaceText))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 180, alignment: .leading)
                    .lineLimit(1)
                Text(range.note.map(localized) ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(range.note?.hasPrefix("Limited") == true ? Theme.warning.opacity(0.9) : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(localizedFormat("~%lld s", Int64(range.estimatedSeconds)))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                if let remove {
                    Button(action: remove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bare)
                    .keyboardFocusable()
                    .help(localized("Remove this range"))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bare)
        .keyboardFocusable()
        .hoverHighlight(cornerRadius: 0)
        .accessibilityValue(localized(range.isSelected ? "Selected" : "Not selected"))
    }

    private var interfaceText: String {
        if let interface = range.interface {
            return [interface, range.kind].compactMap { $0 }.joined(separator: " · ")
        }
        return localized("Added range")
    }
}
