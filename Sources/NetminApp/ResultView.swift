import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A finished run. The summary is built from the output on the fly; the raw text stays one
/// click away through Copy Result and the saved report.
struct ResultView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var runner: CommandRunner
    @ObservedObject private var store = NetminProStore.shared
    let run: ToolRun
    @State private var saveError: String?
    @State private var copiedNote: String?

    init(model: AppModel, run: ToolRun) {
        self.model = model
        self.run = run
        _runner = ObservedObject(wrappedValue: model.runner)
    }

    private var summary: ResultSummary { model.summary(for: run) }
    private var insight: ResultInsight? { ResultInterpreter.insight(for: run) }

    var body: some View {
        let summary = summary
        let insight = insight
        VStack(spacing: 0) {
            header(summary: summary, insight: insight)
            Rectangle().fill(Theme.border).frame(height: 1)
            if model.showsRawOutput {
                rawOutput
            } else if !store.hasFullAccess {
                lockedOverview
            } else {
                overview(summary: summary, insight: insight)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            footer(summary: summary)
        }
    }

    private var lockedOverview: some View {
        VStack(spacing: 14) {
            Image(systemName: "tablecells.badge.ellipsis")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text("Structured reports are a Netmin Pro feature")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Pro turns raw diagnostic output into tables, metrics, and findings. After the 30-day trial, Free includes raw output for up to five requests per day.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("View Netmin Pro…") { store.present(feature: .structuredReports) }
                .buttonStyle(.netmin(.primary))
                .keyboardFocusable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func overview(summary: ResultSummary, insight: ResultInsight?) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let insight {
                        InsightBanner(insight: insight, run: run, model: model)
                    }
                    if insight?.severity != .error {
                        if !summary.sections.isEmpty || !summary.devices.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(localized(summary.title))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(localized(summary.detail))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 2)
                        }
                        if !summary.metrics.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                                ForEach(summary.metrics) { StatTile(metric: $0) }
                            }
                        }
                        if !summary.devices.isEmpty {
                            DeviceTableView(devices: summary.devices, model: model)
                        }
                        ForEach(summary.sections) { SummarySectionView(section: $0) }
                        if summary.sections.isEmpty && summary.devices.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(localized(summary.title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                Text(localized(summary.detail)).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card(padding: 18)
                        }
                    }
                    if let saveError {
                        Label(localized(saveError), systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: 1240, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
    }

    /// The complete command output in a console, for when the interpreted view is not enough.
    private var rawOutput: some View {
        let lines = run.output.split(separator: "\n", omittingEmptySubsequences: false).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Raw output")
                Spacer()
                Text(localizedFormat("%lld lines · %lld characters", Int64(lines), Int64(run.output.count)))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            RawTextView(text: run.output)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(summary: ResultSummary, insight: ResultInsight?) -> some View {
        HStack(spacing: 14) {
            ToolIconTile(symbol: run.tool.symbolName, size: 44, category: run.tool.visualCategory)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.tool.localizedTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 5) {
                    if let subtitle = summary.subtitle {
                        Text(localized(subtitle)).font(.system(size: 13))
                    } else if run.target.isEmpty {
                        Text("No target").font(.system(size: 13))
                    } else {
                        Text(run.target).font(Theme.mono(12.5)).textSelection(.enabled)
                    }
                    Text("·").font(.system(size: 13))
                    RelativeTimeText(date: run.startedAt).font(.system(size: 13))
                }
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            }
            Spacer()
            SegmentedControl(options: ["Overview", "Raw output"], selection: Binding(
                get: { model.showsRawOutput ? 1 : 0 },
                set: { model.showsRawOutput = $0 == 1 }
            ))
            .help(localized("Remembered for the next results · ⌘1 Overview, ⌘2 Raw output"))
            StatusPill(tone: statusTone(insight), text: localizedFormat("%@ · %@ s", localized(statusLabel(insight)), run.duration.formatted(.number.precision(.fractionLength(1)))))
            IconButton(symbol: "arrow.clockwise", help: "Run again") { model.rerun(run) }
        }
        .padding(.horizontal, 32)
        .frame(height: 84)
    }

    private func statusTone(_ insight: ResultInsight?) -> SummaryTone {
        insight?.severity == .error ? .negative : insight?.severity == .warning ? .warning : .positive
    }

    private func statusLabel(_ insight: ResultInsight?) -> String {
        insight?.severity == .error ? "Failed" : insight?.severity == .warning ? "Partial" : "Complete"
    }

    private func footer(summary: ResultSummary) -> some View {
        HStack(spacing: 10) {
            Button(newLabel) { model.newLookup() }
                .buttonStyle(.netmin(.ghost, shortcut: "esc"))
                .keyboardFocusable()
                .keyboardShortcut(.cancelAction)
            Spacer()
            if let copiedNote {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(localizedFormat("Copied %@", localized(copiedNote)))
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.success)
                .transition(.opacity)
            }
            Button {
                if store.hasFullAccess {
                    saveReport(summary: summary)
                } else {
                    store.present(feature: .structuredReports)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 12, weight: .semibold))
                    Text(localized(store.hasFullAccess ? "Save Report…" : "Unlock Report…"))
                }
            }
            .buttonStyle(.netmin(.secondary))
            .keyboardFocusable()
            // ⌘⇧C itself is served by the Tools menu, so the control only advertises it.
            SplitButton(title: "Copy Result", shortcut: "⌘⇧C", action: { copy(run.output, note: "raw output") }, items: copyMenuItems(summary: summary))
        }
        .padding(.horizontal, 32)
        .frame(height: 72)
        .animation(.easeOut(duration: 0.2), value: copiedNote)
    }

    private func copyMenuItems(summary: ResultSummary) -> [SplitMenuItem] {
        var items = [SplitMenuItem("Copy Raw Output") { copy(run.output, note: "raw output") }]
        if store.hasFullAccess {
            items.append(SplitMenuItem("Copy Summary") { copy(ResultInterpreter.plainText(for: summary), note: "summary") })
        } else {
            items.append(SplitMenuItem("Unlock Structured Summary…") {
                store.present(feature: .structuredReports)
            })
        }
        items.append(SplitMenuItem("Copy Command") { copy(run.command, note: "command") })
        if !run.target.isEmpty {
            items.append(.divider)
            items.append(SplitMenuItem("Copy Target") { copy(run.target, note: "target") })
        }
        return items
    }

    private var newLabel: String {
        if run.tool.isLocalDeviceSweep { return localized("New Sweep") }
        if run.tool.group == "Reports" { return localized("New Report") }
        return localized("New Lookup")
    }

    private func copy(_ text: String, note: String) {
        model.copy(text)
        copiedNote = note
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if copiedNote == note { copiedNote = nil }
        }
    }

    private func saveReport(summary: ResultSummary) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(run.tool.title.replacingOccurrences(of: " ", with: "-"))-report.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let report = """
        \(run.tool.title)
        Target: \(run.target)
        Command: \(run.command)
        Started: \(run.startedAt.formatted(date: .abbreviated, time: .standard))
        Duration: \(run.duration.formatted(.number.precision(.fractionLength(1)))) s

        \(ResultInterpreter.plainText(for: summary))

        Raw output
        \(run.output)
        """
        do { try report.write(to: url, atomically: true, encoding: .utf8); saveError = nil }
        catch { saveError = error.localizedDescription }
    }
}

/// A translucent warning or error action that stays within the banner's color family.
private struct InsightActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        InsightActionButtonBody(configuration: configuration, tint: tint)
    }
}

private struct InsightActionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint.opacity(foregroundOpacity))
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: Theme.smallControlHeight)
            .background(tint.opacity(fillOpacity), in: shape)
            .overlay(shape.stroke(tint.opacity(borderOpacity), lineWidth: 1))
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), .clear, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(0.5)
            )
            .shadow(color: tint.opacity(hovering ? 0.16 : 0.06), radius: hovering ? 6 : 2, y: 1)
            .contentShape(shape)
            .onHover { hovering = isEnabled && $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var foregroundOpacity: Double {
        guard isEnabled else { return 0.42 }
        return configuration.isPressed ? 0.78 : 1
    }

    private var fillOpacity: Double {
        guard isEnabled else { return 0.05 }
        if configuration.isPressed { return 0.24 }
        return hovering ? 0.18 : 0.12
    }

    private var borderOpacity: Double {
        guard isEnabled else { return 0.10 }
        if configuration.isPressed { return 0.55 }
        return hovering ? 0.45 : 0.30
    }
}

private struct InsightBanner: View {
    let insight: ResultInsight
    let run: ToolRun
    @ObservedObject var model: AppModel

    private var color: Color { insight.severity == .error ? Theme.danger : Theme.warning }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: insight.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(localized(insight.title))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                Text(localized(insight.detail))
                    .font(insight.severity == .error ? Theme.mono(12.5) : .system(size: 13))
                    .foregroundStyle(insight.severity == .error ? Theme.textPrimary.opacity(0.85) : Theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button("Copy error") { model.copy(insight.detail) }
                    .buttonStyle(InsightActionButtonStyle(tint: color))
                    .keyboardFocusable()
                if insight.severity == .warning, run.tool.title == "WHOIS" {
                    Button("Retry registry") { model.retryWHOIS(run: run) }
                        .buttonStyle(InsightActionButtonStyle(tint: color))
                        .keyboardFocusable()
                    Button("Try RDAP instead →") { model.tryRDAP(for: run) }
                        .buttonStyle(.netmin(.link, size: .small))
                        .keyboardFocusable()
                }
            }
        }
        .padding(16)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(color.opacity(0.35), lineWidth: 1))
    }
}
