import AppKit
import Foundation

/// One candidate network in the Local Device Sweep form: detected from this Mac's interfaces or
/// typed by the user.
struct SweepRange: Identifiable, Hashable {
    let cidr: String
    let interface: String?
    let kind: String?
    let note: String?
    let estimatedSeconds: Int
    let isCustom: Bool
    var isSelected: Bool
    var id: String { cidr }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tools: [ToolDefinition]
    @Published var selectedToolID: String?
    @Published var sidebarQuery = ""
    @Published var target = ""
    @Published var resolver = ""
    @Published var useCustomResolver = false
    @Published var optionEnabled = false
    @Published var catalogError: String?
    @Published private(set) var favoriteToolIDs = Set(
        UserDefaults.standard.stringArray(forKey: AppModel.favoriteToolIDsKey) ?? []
    )
    @Published var sweepRanges: [SweepRange] = []
    @Published var rangeDraft = ""
    /// Which side of the result view opens first. The last choice is remembered, so switching
    /// to Raw output once makes every later result open there until switched back.
    @Published var showsRawOutput = UserDefaults.standard.bool(forKey: AppModel.rawOutputKey) {
        didSet { defaults.set(showsRawOutput, forKey: AppModel.rawOutputKey) }
    }
    let runner = CommandRunner()

    private let defaults = UserDefaults.standard
    private let recentTargetsKey = "NetminRecentTargets"
    private let legacyRecentRunsKey = "NetminRecentRuns"
    private static let rawOutputKey = "NetminShowsRawOutput"
    private static let favoriteToolIDsKey = "NetminFavoriteToolIDs"
    private var summaryCache: (startedAt: Date, summary: ResultSummary)?

    init() {
        do {
            let loaded = try ToolCatalog.loadBundled()
            tools = loaded
            selectedToolID = loaded.first?.id
            optionEnabled = loaded.first?.optionDefault ?? false
            let validIDs = Set(loaded.map(\.id))
            let validFavorites = favoriteToolIDs.intersection(validIDs)
            if validFavorites != favoriteToolIDs {
                favoriteToolIDs = validFavorites
                defaults.set(validFavorites.sorted(), forKey: AppModel.favoriteToolIDsKey)
            }
        } catch {
            tools = []
            catalogError = error.localizedDescription
        }
        // Recent-run summaries only powered the retired command palette. Remove the legacy cache
        // rather than retaining diagnostic metadata that the current interface never displays.
        defaults.removeObject(forKey: legacyRecentRunsKey)
        if selectedTool?.isLocalDeviceSweep == true { refreshSweepRanges() }
    }

    var selectedTool: ToolDefinition? {
        tools.first { $0.id == selectedToolID }
    }

    var visibleGroups: [ToolGroup] {
        let needle = sidebarQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = needle.isEmpty ? tools : tools.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.localizedTitle.localizedCaseInsensitiveContains(needle)
                || $0.summary.localizedCaseInsensitiveContains(needle)
                || $0.localizedSummary.localizedCaseInsensitiveContains(needle)
                || $0.group.localizedCaseInsensitiveContains(needle)
                || $0.localizedGroup.localizedCaseInsensitiveContains(needle)
        }
        let favorites = visible.filter { favoriteToolIDs.contains($0.id) }
        let groups = ToolCatalog.groups(from: visible.filter { !favoriteToolIDs.contains($0.id) })
        guard !favorites.isEmpty else { return groups }
        // A tool has one sidebar row: favoriting moves it to the top instead of creating duplicate
        // List selection tags that would make arrow-key navigation ambiguous.
        return [ToolGroup(name: "Favorites", tools: favorites)] + groups
    }

    func isFavorite(_ tool: ToolDefinition) -> Bool {
        favoriteToolIDs.contains(tool.id)
    }

    func toggleFavorite(_ tool: ToolDefinition) {
        var updated = favoriteToolIDs
        if updated.contains(tool.id) {
            updated.remove(tool.id)
        } else {
            updated.insert(tool.id)
        }
        favoriteToolIDs = updated
        defaults.set(updated.sorted(), forKey: AppModel.favoriteToolIDsKey)
    }

    var recentTargets: [String] {
        defaults.stringArray(forKey: recentTargetsKey) ?? []
    }

    /// The most recent target that is a usable IPv4 range, offered as a chip in the sweep form.
    var recentRange: String? {
        recentTargets.first { text in
            if case .cidr = TargetInput.classify(text), TargetInput.isIPv4(String(text.split(separator: "/").first ?? "")) { return true }
            return false
        }
    }

    var targetKind: TargetKind {
        selectedTool?.validatedTargetKind(target) ?? TargetInput.classify(target)
    }

    var secondaryInputKind: TargetKind {
        guard let tool = selectedTool else { return TargetInput.classify(resolver) }
        if tool.usesResolver { return tool.validatedSecondaryInputKind(resolver) }
        return TargetPolicy.hostOrIP.validatedKind(resolver, expected: localized("DNS server"))
    }

    var canRun: Bool {
        guard let tool = selectedTool, !runner.isRunning else { return false }
        if tool.isLocalDeviceSweep {
            return sweepRanges.isEmpty || sweepRanges.contains(where: \.isSelected)
        }
        if tool.requiresTarget && target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if tool.usesTarget && targetKind.isInvalid { return false }
        if tool.usesResolver || (tool.supportsCustomResolver && useCustomResolver) {
            let value = resolver.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || secondaryInputKind.isInvalid { return false }
        }
        return true
    }

    func runButtonTitle(for tool: ToolDefinition) -> String {
        if tool.isLocalDeviceSweep { return localized("Run Sweep") }
        if tool.group == "Reports" { return localized("Run Report") }
        if tool.usesTarget { return localized("Run Lookup") }
        return localized("Run Tool")
    }

    func select(_ tool: ToolDefinition) {
        selectedToolID = tool.id
        optionEnabled = tool.optionDefault
        useCustomResolver = false
        resolver = ""
        runner.clear()
        if tool.isLocalDeviceSweep { refreshSweepRanges() }
    }

    /// Clears the form without changing the selected tool.
    func resetForm() {
        target = ""
        resolver = ""
        useCustomResolver = false
        rangeDraft = ""
        optionEnabled = selectedTool?.optionDefault ?? false
        if selectedTool?.isLocalDeviceSweep == true { refreshSweepRanges() }
    }

    func runSelected() {
        guard canRun, let tool = selectedTool else { return }
        let cleanedTarget: String
        if tool.isLocalDeviceSweep {
            cleanedTarget = sweepTarget
        } else {
            cleanedTarget = tool.usesTarget ? target.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        }
        guard beginDiagnosticRequest() else { return }
        if tool.isLocalDeviceSweep {
            for range in sweepRanges where range.isCustom && range.isSelected { remember(range.cidr) }
        } else if tool.usesTarget {
            remember(cleanedTarget)
        }
        let resolverEnabled = tool.usesResolver || (tool.supportsCustomResolver && useCustomResolver)
        runner.start(tool: tool, target: cleanedTarget,
                     resolver: resolverEnabled ? resolver.trimmingCharacters(in: .whitespacesAndNewlines) : "",
                     optionEnabled: optionEnabled)
    }

    /// Runs a tool against a value chosen from a result, such as pinging a discovered device.
    func run(toolTitled title: String, target value: String) {
        guard let tool = tools.first(where: { $0.title == title }) else { return }
        select(tool)
        target = value
        runSelected()
    }

    /// Repeats a finished run with exactly the same inputs.
    func rerun(_ run: ToolRun) {
        guard beginDiagnosticRequest() else { return }
        runner.start(tool: run.tool, target: run.target, resolver: run.resolver, optionEnabled: run.optionEnabled)
    }

    func newLookup() {
        runner.clear()
    }

    func clearRecentData() {
        defaults.removeObject(forKey: recentTargetsKey)
        defaults.removeObject(forKey: legacyRecentRunsKey)
        objectWillChange.send()
    }

    func retryWHOIS(run: ToolRun) {
        guard let server = ResultInterpreter.referralServer(in: run.output) else { return }
        let retry = ToolDefinition(
            id: run.tool.id,
            group: run.tool.group,
            title: run.tool.title,
            command: "/usr/bin/whois -h \"$2\" \"$1\"",
            placeholder: run.tool.placeholder,
            resolverPlaceholder: "WHOIS server",
            summary: run.tool.summary,
            optionLabel: nil,
            optionArgument: nil,
            optionDefault: false,
            progressMessage: localizedFormat("Querying %@…", server)
        )
        guard beginDiagnosticRequest() else { return }
        runner.start(tool: retry, target: run.target, resolver: server, optionEnabled: false)
    }

    func tryRDAP(for run: ToolRun) {
        guard let rdap = tools.first(where: { $0.title == "RDAP Domain" }) else { return }
        select(rdap)
        target = run.target
        runSelected()
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Every command launch uses one allowance; opening, copying, or exporting a result does not.
    private func beginDiagnosticRequest() -> Bool {
        let store = NetminProStore.shared
        guard store.beginDiagnosticRequest() else {
            store.present(feature: .unlimitedRequests)
            return false
        }
        return true
    }

    /// The interpreted summary for a finished run, computed once per run.
    func summary(for run: ToolRun) -> ResultSummary {
        if let cached = summaryCache, cached.startedAt == run.startedAt { return cached.summary }
        let summary = ResultInterpreter.summary(for: run)
        summaryCache = (run.startedAt, summary)
        return summary
    }

    // MARK: - Local Device Sweep

    var selectedSweepRanges: [SweepRange] { sweepRanges.filter(\.isSelected) }

    /// A blank target lets the helper discover networks itself, which matches "all detected".
    var sweepTarget: String {
        let selected = selectedSweepRanges
        let allDetectedSelected = sweepRanges.filter { !$0.isCustom }.allSatisfy(\.isSelected)
        if allDetectedSelected, !selected.contains(where: \.isCustom) { return "" }
        return selected.map(\.cidr).joined(separator: ",")
    }

    var sweepEstimateSeconds: Int {
        let ranges = selectedSweepRanges
        return ranges.isEmpty ? 0 : 4 + ranges.reduce(0) { $0 + $1.estimatedSeconds }
    }

    func refreshSweepRanges() {
        let custom = sweepRanges.filter(\.isCustom)
        let detected = LocalNetworks.detect().map { network -> SweepRange in
            var notes: [String] = []
            if let gateway = network.gateway, !gateway.isEmpty {
                notes.append(localizedFormat("Gateway %@ · default route", gateway))
            } else if network.isPrimary {
                notes.append(localized("Default route"))
            }
            if network.isLimitedToLocal24 { notes.append(localized("Limited to the local /24 for speed")) }
            return SweepRange(
                cidr: network.scannedCIDR,
                interface: network.interface,
                kind: network.kind,
                note: notes.isEmpty ? nil : notes.joined(separator: " · "),
                estimatedSeconds: network.estimatedSeconds,
                isCustom: false,
                isSelected: true
            )
        }
        sweepRanges = detected + custom.filter { range in !detected.contains { $0.cidr == range.cidr } }
    }

    func toggleRange(_ id: String) {
        guard let index = sweepRanges.firstIndex(where: { $0.id == id }) else { return }
        sweepRanges[index].isSelected.toggle()
    }

    func removeRange(_ id: String) {
        sweepRanges.removeAll { $0.id == id && $0.isCustom }
    }

    /// Validates the typed range the way the helper does and adds it selected.
    @discardableResult
    func addRange(_ text: String? = nil) -> String? {
        let value = (text ?? rangeDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "Enter a range such as 172.16.4.0/22." }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, TargetInput.isIPv4(String(parts[0])), let prefix = Int(parts[1]), (0...30).contains(prefix) else {
            return "Enter an IPv4 range with a prefix from /0 to /30, for example 192.168.1.0/24."
        }
        guard let address = LocalNetworks.ipv4Value(String(parts[0])) else { return "The address is not valid." }
        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << UInt32(32 - prefix)
        let cidr = "\(LocalNetworks.ipv4String(address & mask))/\(prefix)"
        if let index = sweepRanges.firstIndex(where: { $0.cidr == cidr }) {
            sweepRanges[index].isSelected = true
        } else {
            guard sweepRanges.filter(\.isCustom).count < 16 else {
                return "A sweep can include at most 16 manually added ranges."
            }
            sweepRanges.append(SweepRange(
                cidr: cidr, interface: nil, kind: nil,
                note: localized(prefix < 22 ? "Limited to the local /24 for speed" : "Added manually"),
                estimatedSeconds: LocalNetworks.estimate(cidr: cidr) ?? 6,
                isCustom: true, isSelected: true
            ))
        }
        rangeDraft = ""
        return nil
    }

    private func remember(_ value: String) {
        guard !value.isEmpty else { return }
        var targets = recentTargets.filter { $0.caseInsensitiveCompare(value) != .orderedSame }
        targets.insert(value, at: 0)
        defaults.set(Array(targets.prefix(8)), forKey: recentTargetsKey)
        objectWillChange.send()
    }
}
