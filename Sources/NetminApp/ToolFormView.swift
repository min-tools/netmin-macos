import AppKit
import SwiftUI

struct ToolFormView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var runner: CommandRunner
    @ObservedObject private var store = NetminProStore.shared
    let tool: ToolDefinition
    @State private var targetFocused = false
    @State private var resolverFocused = false

    init(model: AppModel, tool: ToolDefinition) {
        self.model = model
        self.tool = tool
        _runner = ObservedObject(wrappedValue: model.runner)
    }

    var body: some View {
        VStack(spacing: 0) {
            if runner.isRunning {
                RunningView(tool: tool, runner: runner)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        toolHeader
                        if tool.isLocalDeviceSweep {
                            SweepFormView(model: model)
                        } else {
                            if tool.usesTarget { targetSection }
                            if tool.usesResolver { resolverSection }
                            if tool.supportsCustomResolver { customResolverSection }
                            if tool.optionLabel != nil { optionSection }
                        }
                        if let error = runner.launchError {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.danger)
                                Text(localized(error)).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.danger.opacity(0.35), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 36)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 1080, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                bottomBar
            }
        }
    }

    private var toolHeader: some View {
        HStack(spacing: 18) {
            ToolIconTile(symbol: tool.symbolName, size: 60)
            VStack(alignment: .leading, spacing: 5) {
                Text(tool.localizedTitle)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(tool.localizedSummary)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var targetSection: some View {
        let kind = model.targetKind
        return VStack(alignment: .leading, spacing: 10) {
            // The caption row keeps one height whether or not a detected kind is shown, so the
            // field never shifts while typing.
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(tool.requiresTarget ? "Target" : "Target (optional)")
                Spacer()
                Text(kind.description.isEmpty ? " " : localized(kind.description))
                    .font(.system(size: 12.5))
                    .foregroundStyle(kind.isInvalid ? Theme.danger : Theme.textSecondary)
                    .opacity(kind.description.isEmpty ? 0 : 1)
            }
            .frame(height: 18)
            TargetField(placeholder: tool.localizedPlaceholder, text: $model.target, kind: kind, isFocused: $targetFocused) {
                model.runSelected()
            }
            if !model.recentTargets.isEmpty {
                HStack(spacing: 8) {
                    Text("Recent").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    ForEach(model.recentTargets.prefix(4), id: \.self) { recent in
                        Button { model.target = recent } label: { Chip(text: recent) }
                            .buttonStyle(.bare)
                            .keyboardFocusable()
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: kind.description)
    }

    private var resolverSection: some View {
        let kind = model.secondaryInputKind
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(tool.secondaryInputLabel)
                Spacer()
                Text(kind.description.isEmpty ? " " : localized(kind.description))
                    .font(.system(size: 12.5))
                    .foregroundStyle(kind.isInvalid ? Theme.danger : Theme.textSecondary)
                    .opacity(kind.description.isEmpty ? 0 : 1)
            }
            .frame(height: 18)
            TargetField(placeholder: tool.localizedResolverPlaceholder ?? localized("DNS server"), text: $model.resolver,
                        kind: kind, isFocused: $resolverFocused) {
                model.runSelected()
            }
        }
    }

    private var customResolverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                model.useCustomResolver.toggle()
                if model.useCustomResolver {
                    DispatchQueue.main.async { resolverFocused = true }
                } else {
                    model.resolver = ""
                }
            } label: {
                HStack(spacing: 10) {
                    CheckMark(checked: model.useCustomResolver)
                    Text("Use custom resolver")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.bare)
            .keyboardFocusable()

            if model.useCustomResolver { resolverSection }
        }
        .animation(.easeOut(duration: 0.15), value: model.useCustomResolver)
    }

    @ViewBuilder private var optionSection: some View {
        if tool.title == "Network Lookup" {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Depth")
                HStack(spacing: 16) {
                    SegmentedControl(options: ["Quick", "Full"], selection: Binding(
                        get: { model.optionEnabled ? 0 : 1 },
                        set: { model.optionEnabled = $0 == 0 }
                    ))
                    Text(localized(model.optionEnabled
                         ? "DNS records, geolocation and ASN. Usually a few seconds."
                         : "Adds reachability, common ports and the route. Can take a minute."))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } else if tool.title == "DNS Zone Discovery" {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Depth")
                HStack(spacing: 16) {
                    SegmentedControl(options: ["Quick", "Deep"], selection: Binding(
                        get: { model.optionEnabled ? 1 : 0 },
                        set: { model.optionEnabled = $0 == 1 }
                    ))
                    Text(localized(model.optionEnabled
                         ? "Adds zone-transfer attempts, DNSSEC signals, more hostnames, and certificate names."
                         : "Checks apex records, mail policies, services, common hosts, and DKIM selectors."))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } else if tool.title == "DNS Propagation" {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Records")
                HStack(spacing: 16) {
                    SegmentedControl(options: ["Primary", "All relevant"], selection: Binding(
                        get: { model.optionEnabled ? 1 : 0 },
                        set: { model.optionEnabled = $0 == 1 }
                    ))
                    Text(localized(model.optionEnabled
                         ? "Compares the common record types that apply to this target."
                         : "Checks A for a hostname, PTR for an IP address, or SRV for a service name."))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } else if let label = tool.optionLabel {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Options")
                ToggleCard(title: localized(label), subtitle: tool.optionArgument.map { localizedFormat("Passes %@ to the command", $0) } ?? localized("Enables the tool's optional behaviour"),
                           isOn: $model.optionEnabled)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            footerHint
            Spacer()
            Button("Cancel") { model.resetForm() }
                .buttonStyle(.netmin(.ghost, shortcut: "esc"))
                .keyboardFocusable()
                .keyboardShortcut(.cancelAction)
            Button {
                model.runSelected()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                    Text(model.runButtonTitle(for: tool))
                }
            }
            .buttonStyle(.netmin(.primary, shortcut: "⌘↩"))
            .keyboardFocusable()
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canRun)
        }
        .padding(.horizontal, 40)
        .frame(height: 72)
    }

    @ViewBuilder private var footerHint: some View {
        if store.hasPreparedFreeAccess && !store.hasFullAccess {
            Text(localizedFormat("Free · %lld of %lld requests left today", Int64(store.freeRequestsRemainingToday), Int64(NetminFreeAccessPolicy.dailyRequestLimit)))
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).monospacedDigit()
        } else if tool.isLocalDeviceSweep {
            let selected = model.selectedSweepRanges.count
            if model.sweepRanges.isEmpty {
                Text("No private IPv4 network detected · add a range to scan")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            } else {
                Text(localizedFormat("%lld of %lld networks · about %lld s", Int64(selected), Int64(model.sweepRanges.count), Int64(model.sweepEstimateSeconds)))
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).monospacedDigit()
            }
        }
    }
}

private struct RunningView: View {
    let tool: ToolDefinition
    @ObservedObject var runner: CommandRunner

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ToolIconTile(symbol: tool.symbolName, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.localizedTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(tool.localizedProgressMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(runner.startedAt ?? context.date)
                    StatusPill(tone: .accent, text: localizedFormat("Running · %@ s", elapsed.formatted(.number.precision(.fractionLength(0)))), pulsing: true)
                }
                Button(tool.isLocalDeviceSweep ? "Stop Sweep" : "Stop") { runner.cancel() }
                    .buttonStyle(.netmin(.danger, shortcut: "esc"))
                    .keyboardFocusable()
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 32)
            .frame(height: 84)
            // Same 84 pt header and 1 pt rule as the result view, so nothing moves when a run
            // starts or finishes; the progress stripe rides on the rule instead of adding height.
            Rectangle().fill(Theme.border).frame(height: 1)
                .overlay(ProgressStripe().frame(height: 2))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel("Raw output")
                    Spacer()
                    Text(localizedFormat("%lld lines · %lld characters", Int64(lineCount), Int64(runner.output.count)))
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary).monospacedDigit()
                }
                RawTextView(text: consoleText, followsTail: true)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
    }

    private var lineCount: Int {
        runner.output.isEmpty ? 0 : runner.output.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var consoleText: String {
        if runner.output.isEmpty {
            return localized("Waiting for the first response…")
        }
        return runner.output
    }
}

/// Prevent AppKit from centring a temporarily narrow live document during its first layout pass.
private final class ConsoleClipView: NSClipView {
    var keepsLeadingEdge = false

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        if keepsLeadingEdge { bounds.origin.x = 0 }
        return bounds
    }
}

/// Keeps the document pinned to the leading edge while AppKit resolves its initial size.
private final class ConsoleScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView else { return }
        var frame = textView.frame
        frame.origin.x = 0
        frame.size.width = max(frame.width, contentView.bounds.width)
        frame.size.height = max(frame.height, contentView.bounds.height)
        if frame != textView.frame { textView.frame = frame }
    }
}

/// A read-only console for streaming output. It keeps following the tail while a command runs.
struct RawTextView: NSViewRepresentable {
    let text: String
    var followsTail = false

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ConsoleScrollView()
        let clipView = ConsoleClipView()
        clipView.keepsLeadingEdge = followsTail
        scroll.contentView = clipView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.selectedTextAttributes = [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.35)]
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        if followsTail {
            // Following a long line can also move AppKit's horizontal origin. Keep the live
            // console aligned with the finished console and follow only the vertical tail.
            textView.scrollToEndOfDocument(nil)
            var origin = scroll.contentView.bounds.origin
            origin.x = 0
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}
