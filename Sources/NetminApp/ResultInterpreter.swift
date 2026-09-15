import Foundation

enum InsightSeverity { case information, warning, error }

struct ResultInsight: Identifiable {
    let severity: InsightSeverity
    let title: String
    let detail: String
    var id: String { title + detail }
}

struct ResultField: Identifiable {
    let label: String
    let value: String
    var id: String { label + value }
}

/// Semantic colour applied by the result view to a metric, row, or badge.
enum SummaryTone { case neutral, accent, positive, warning, negative }

struct SummaryMetric: Identifiable {
    let label: String
    let value: String
    var unit: String? = nil
    var detail: String? = nil
    var tone: SummaryTone = .neutral
    var usesCompactValueStyle = false
    var id: String { label + value }
}

struct SummaryRow: Identifiable {
    let label: String
    let value: String
    var tone: SummaryTone = .neutral
    var id: String { label + value }
}

/// A columnar block rendered as a table; `monospaced` lists column indexes shown in the code font
/// and `statusColumn` names the column whose words such as "open" or "timed out" are colour-coded.
struct SummaryTable {
    let columns: [String]
    let rows: [[String]]
    var monospaced: Set<Int> = []
    var statusColumn: Int? = nil
}

struct SummarySection: Identifiable {
    let title: String
    let detail: String?
    let rows: [SummaryRow]
    let body: String?
    var table: SummaryTable? = nil
    var badge: String? = nil
    var tone: SummaryTone = .neutral
    var omittedLines = 0
    var id: String { title + (detail ?? "") }
}

struct DiscoveredDevice: Identifiable {
    let address: String
    let name: String?
    let latency: Double?
    let interface: String
    let mac: String?
    let note: String?
    var services: [String] = []
    var isThisMac = false
    var isGateway = false
    var id: String { address }
}

struct SweepNetwork: Identifiable {
    let cidr: String
    let interface: String
    let limited: Bool
    var id: String { cidr + interface }
}

struct ResultSummary {
    let title: String
    let detail: String
    let metrics: [SummaryMetric]
    let sections: [SummarySection]
    var devices: [DiscoveredDevice] = []
    var networks: [SweepNetwork] = []
    var subtitle: String? = nil
    var headline: String? = nil
}

enum ResultInterpreter {
    /// Plain labels emitted by the composite-report helpers. Keeping this list explicit prevents
    /// ordinary output lines from being mistaken for section boundaries.
    private static let reportSectionLabels: Set<String> = [
        "Basic", "Address and ownership", "DNS", "Lookup complete", "Reachability",
        "Common TCP ports", "Route", "Discovered endpoints", "Port and TLS checks",
        "TCP reachability", "HTTPS headers", "TLS certificate and chain", "TLS handshakes",
        "Primary MX STARTTLS", "Authoritative DNS", "Zone transfer attempts",
        "Complete zone transfer", "Discovery status", "Zone apex records",
        "Mail and domain policies", "Standard services", "Common hostnames",
        "Common DKIM selectors", "DNSSEC enumeration signals",
        "Certificate transparency names", "Wildcard check"
    ]

    static func insight(for run: ToolRun) -> ResultInsight? {
        if run.exitCode != 0 {
            return ResultInsight(
                severity: .error,
                title: run.tool.summaryKind == .document
                    ? localizedFormat("%@ could not be retrieved", run.tool.localizedTitle)
                    : localizedFormat("%@ did not complete", run.tool.localizedTitle),
                detail: failureDetail(from: run.output, status: run.exitCode)
            )
        }
        if run.tool.title == "WHOIS", let referral = referralServer(in: run.output),
           run.output.localizedCaseInsensitiveContains("IANA WHOIS server"),
           !hasCompleteWHOISRecord(run.output) {
            return ResultInsight(
                severity: .warning,
                title: "Registry response is incomplete",
                detail: localizedFormat("Only the IANA referral was returned. Retry %@ or use RDAP to retrieve the registrar, nameservers, and registration dates.", referral)
            )
        }
        if run.tool.title == "DNS Zone Discovery",
           run.output.contains("Completeness: Partial discovery") {
            return ResultInsight(
                severity: .warning,
                title: "Public DNS discovery is partial",
                detail: "The authoritative servers did not provide a complete zone transfer. These are the records found through public probes; custom names may still exist."
            )
        }
        // A sweep that reached the device table without any entries deserves a visible explanation.
        if run.tool.title == "Local Device Sweep", capture(#"Devices \((\d+) found\)"#, in: run.output) == "0" {
            return ResultInsight(
                severity: .warning,
                title: "No devices responded",
                detail: "Nothing answered ping or appeared in the neighbor cache on the scanned networks. Check that this Mac is on the expected network or add a range manually."
            )
        }
        return nil
    }

    static func referralServer(in output: String) -> String? {
        firstValue(named: ["refer", "whois"], in: output)
    }

    static func fields(for run: ToolRun) -> [ResultField] {
        summary(for: run).sections.flatMap(\.rows).map { ResultField(label: $0.label, value: $0.value) }
    }

    static func summary(for run: ToolRun) -> ResultSummary {
        let clean = run.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return ResultSummary(
                title: run.succeeded ? "No data returned" : "No diagnostic output",
                detail: run.succeeded
                    ? "The command completed, but the target returned no matching data."
                    : "The command failed before it produced diagnostic output.",
                metrics: [SummaryMetric(label: "Exit status", value: String(run.exitCode),
                                        tone: run.succeeded ? .positive : .negative)],
                sections: []
            )
        }

        // Failed command output is diagnostic text, not successful tool data. Keeping it out of
        // the normal interpreters prevents errors such as curl messages from becoming fake records.
        if !run.succeeded {
            return ResultSummary(
                title: "No result returned",
                detail: failureDetail(from: run.output, status: run.exitCode),
                metrics: [SummaryMetric(label: "Exit status", value: String(run.exitCode), tone: .negative)],
                sections: []
            )
        }

        switch run.tool.summaryKind {
        case .report:
            return reportSummary(run)
        case .publicAddress:
            return publicAddressSummary(run)
        case .discovery:
            return discoverySummary(run)
        case .networkTable:
            return networkTableSummary(run)
        case .configuration:
            return configurationSummary(run)
        case .registration:
            return registrationSummary(run)
        case .dnsRecords:
            return dnsSummary(run)
        case .latency:
            return latencySummary(run)
        case .tls:
            return tlsSummary(run)
        case .http:
            return httpSummary(run)
        case .port:
            return portSummary(run)
        case .document:
            return documentSummary(run)
        case .utility:
            return utilitySummary(run)
        }
    }

    /// Text rendering of a summary for the clipboard and saved reports.
    static func plainText(for summary: ResultSummary) -> String {
        var lines: [String] = [localized(summary.title), localized(summary.detail), ""]
        for metric in summary.metrics {
            var line = "\(localized(metric.label)): \(localized(metric.value))"
            if let unit = metric.unit { line += " \(localized(unit))" }
            if let detail = metric.detail { line += " (\(localized(detail)))" }
            lines.append(line)
        }
        if !summary.devices.isEmpty {
            lines.append("")
            lines.append(localizedFormat("Devices (%lld)", Int64(summary.devices.count)))
            for device in summary.devices {
                let latency = device.latency.map { formatMilliseconds($0) } ?? localized("no reply")
                lines.append("\(device.address)\t\(device.name ?? "-")\t\(latency)\t\(device.interface)\t\(device.mac ?? "-")")
            }
        }
        for section in summary.sections {
            lines.append("")
            lines.append(localized(section.title) + (section.badge.map { " · \(localized($0))" } ?? ""))
            if let detail = section.detail { lines.append(localized(detail)) }
            for row in section.rows { lines.append("\(localized(row.label)): \(localized(row.value))") }
            if let table = section.table {
                lines.append(table.columns.map(localized).joined(separator: "\t"))
                for row in table.rows { lines.append(row.map(localized).joined(separator: "\t")) }
            }
            if let body = section.body { lines.append(body) }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Local network discovery

    static func sweepDevices(in output: String) -> [DiscoveredDevice] {
        let gateway = capture(#"^Default gateway: (\S+)$"#, in: output)
        let services = sweepServices(in: output)
        // Horizontal whitespace only: a `\s` gap could otherwise run into the next line.
        let pattern = #"^(\d{1,3}(?:\.\d{1,3}){3})[ \t]+(.+?)[ \t]+(-|[0-9.]+ ms)[ \t]+(\S+)[ \t]+(\S+)[ \t]+(.*)$"#
        return allMatches(pattern, in: output).map { groups in
            let isThisMac = groups[1] == "This Mac"
            let name = groups[1] == "-" ? nil : isThisMac ? localized("This Mac") : groups[1]
            let latency = groups[2] == "-" ? nil : Double(groups[2].replacingOccurrences(of: " ms", with: ""))
            let note = groups[5].trimmingCharacters(in: .whitespaces)
            return DiscoveredDevice(
                address: groups[0],
                name: name,
                latency: latency,
                interface: groups[3],
                mac: groups[4] == "-" ? nil : groups[4],
                note: note == "-" || note.isEmpty ? nil : note,
                services: services[groups[0]] ?? [],
                isThisMac: isThisMac,
                isGateway: groups[0] == gateway
            )
        }
    }

    static func sweepNetworks(in output: String) -> [SweepNetwork] {
        allMatches(#"^\s+(\S+/\d+) via (\S+)(?: \((.*)\))?$"#, in: output).map { groups in
            SweepNetwork(cidr: groups[0], interface: groups[1], limited: !groups[2].isEmpty)
        }
    }

    /// Open TCP services keyed by address from the "Common TCP services" block.
    private static func sweepServices(in output: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for line in block(after: "Common TCP services", in: output) {
            guard let groups = firstMatch(#"^(\d{1,3}(?:\.\d{1,3}){3})\s+(.+)$"#, in: line) else { continue }
            result[groups[0]] = groups[1].components(separatedBy: ", ")
        }
        return result
    }

    private static func discoverySummary(_ run: ToolRun) -> ResultSummary {
        if run.tool.title == "Local Device Sweep" {
            let devices = sweepDevices(in: run.output)
            if !devices.isEmpty { return sweepSummary(run, devices: devices) }
        }
        if run.tool.title == "Bonjour Services" {
            let matches = allMatches(#"^\S+[ \t]+Add[ \t]+\d+[ \t]+(\d+)[ \t]+(\S+)[ \t]+(\S+)[ \t]+(.+)$"#, in: run.output)
            let rows = uniqueOrdered(matches.map { groups -> String in
                let transport = groups[2].replacingOccurrences(of: "local.", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return "\(groups[3].trimmingCharacters(in: .whitespaces)).\(transport)\t\(groups[1] == "." ? "local." : groups[1])\t\(groups[0])"
            }).map { $0.components(separatedBy: "\t") }
            if !rows.isEmpty {
                let table = SummaryTable(columns: ["Service type", "Domain", "Interface"], rows: rows, monospaced: [0])
                return ResultSummary(
                    title: "Advertised Bonjour services",
                    detail: "Service types announced on the local network during the discovery window.",
                    metrics: [SummaryMetric(label: "Service types", value: String(rows.count), tone: .accent)],
                    sections: [SummarySection(title: "Service types", detail: nil, rows: [], body: nil, table: table)],
                    headline: localizedFormat("%lld service types", Int64(rows.count))
                )
            }
        }
        if run.tool.title == "SSDP/UPnP Discovery" {
            let sections = ssdpSections(run.output)
            if !sections.isEmpty {
                return ResultSummary(
                    title: "UPnP devices and services",
                    detail: "Responses to the multicast search, one card per announcement.",
                    metrics: [SummaryMetric(label: "Responses", value: String(sections.count), tone: .accent)],
                    sections: sections,
                    headline: sections.count == 1
                        ? localized("1 response")
                        : localizedFormat("%lld responses", Int64(sections.count))
                )
            }
        }
        let sections = parsedSections(run.output)
        let lines = usefulLines(run.output)
        let deviceCount = capture(#"Devices\s*\((\d+) found\)"#, in: run.output)
        let rows = keyValueRows(run.output, limit: 30)
        return ResultSummary(
            title: "Discovered network resources",
            detail: "Hosts, advertised services, and reachable endpoints found during this run.",
            metrics: [
                deviceCount.map { SummaryMetric(label: "Devices", value: $0, tone: .accent) },
                SummaryMetric(label: "Lines", value: String(lines.count))
            ].compactMap { $0 },
            sections: !sections.isEmpty ? sections
                : !rows.isEmpty ? [SummarySection(title: "Details", detail: nil, rows: rows, body: nil)]
                : excerptSections(run.output, title: "Discovery results")
        )
    }

    private static func sweepSummary(_ run: ToolRun, devices: [DiscoveredDevice]) -> ResultSummary {
        let networks = sweepNetworks(in: run.output)
        let named = devices.filter { $0.name != nil }.count
        let latencies = devices.compactMap(\.latency).sorted()
        let tcpServices = devices.reduce(0) { $0 + $1.services.count }
        let bonjour = bonjourRows(in: run.output)
        let interfaces = uniqueOrdered(networks.map(\.interface))
        let limited = networks.filter(\.limited).count

        var metrics = [
            SummaryMetric(label: "Devices", value: String(devices.count),
                          detail: localizedFormat("%lld named · %lld unnamed", Int64(named), Int64(devices.count - named)), tone: .accent)
        ]
        if !networks.isEmpty {
            metrics.append(SummaryMetric(
                label: "Networks", value: String(networks.count),
                detail: limited > 0 ? localizedFormat("%lld limited to a /24", Int64(limited)) : interfaces.joined(separator: ", "),
                tone: limited > 0 ? .warning : .neutral
            ))
        }
        if let low = latencies.first, let high = latencies.last {
            let median = latencies[latencies.count / 2]
            metrics.append(SummaryMetric(label: "Latency", value: formatNumber(low), unit: localizedFormat("– %@ ms", formatNumber(high)),
                                         detail: localizedFormat("median %@", formatMilliseconds(median)), tone: .positive))
        } else {
            metrics.append(SummaryMetric(label: "Latency", value: "—", detail: "no ping replies", tone: .warning))
        }
        metrics.append(SummaryMetric(label: "Services", value: String(tcpServices + bonjour.count),
                                     detail: localizedFormat("%lld TCP · %lld Bonjour", Int64(tcpServices), Int64(bonjour.count))))

        var sections: [SummarySection] = []
        if !networks.isEmpty {
            sections.append(SummarySection(
                title: "Networks scanned", detail: nil,
                rows: networks.map {
                    SummaryRow(label: $0.cidr, value: localizedFormat("via %@", $0.interface) + ($0.limited ? " · " + localized("limited to the local /24 for speed") : ""),
                               tone: $0.limited ? .warning : .neutral)
                },
                body: nil
            ))
        }
        let serviceRows = devices.filter { !$0.services.isEmpty }.map { [$0.address, $0.services.joined(separator: ", ")] }
        if !serviceRows.isEmpty {
            sections.append(SummarySection(title: "Common TCP services", detail: "Ports that accepted a connection.", rows: [], body: nil,
                                           table: SummaryTable(columns: ["Address", "Services"], rows: serviceRows, monospaced: [0]),
                                           badge: localizedFormat("%lld hosts", Int64(serviceRows.count))))
        }
        if !bonjour.isEmpty {
            sections.append(SummarySection(title: "Bonjour services", detail: "Advertised during the discovery window.", rows: [], body: nil,
                                           table: SummaryTable(columns: ["Type", "Name"], rows: bonjour),
                                           badge: localizedFormat("%lld entries", Int64(bonjour.count))))
        }
        let networkNoun = localized(networks.count == 1 ? "network" : "networks")
        return ResultSummary(
            title: localizedFormat("%lld devices on %lld %@", Int64(devices.count), Int64(networks.count), networkNoun),
            detail: "Hosts that answered ping or appeared in the neighbor cache, with names, latency, and advertised services.",
            metrics: metrics,
            sections: sections,
            devices: devices,
            networks: networks,
            subtitle: networks.isEmpty ? nil : localizedFormat("%lld %@ · %@", Int64(networks.count), networkNoun, interfaces.joined(separator: ", ")),
            headline: localizedFormat("%lld devices", Int64(devices.count))
        )
    }

    private static func bonjourRows(in output: String) -> [[String]] {
        block(after: "Bonjour services", in: output).compactMap { line in
            guard !line.hasPrefix("No common services") else { return nil }
            let padded = line.padding(toLength: max(line.count, 17), withPad: " ", startingAt: 0)
            let label = String(padded.prefix(16)).trimmingCharacters(in: .whitespaces)
            let name = String(padded.dropFirst(16)).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, !name.isEmpty else { return nil }
            return [label, name]
        }
    }

    private static func ssdpSections(_ output: String) -> [SummarySection] {
        let blocks = output.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        var sections: [SummarySection] = []
        var seen: Set<String> = []
        for block in blocks {
            let rows = keyValueRows(block, limit: 20)
            guard !rows.isEmpty else { continue }
            let server = rows.first { $0.label.caseInsensitiveCompare("server") == .orderedSame }?.value
            let location = rows.first { $0.label.caseInsensitiveCompare("location") == .orderedSame }?.value
            let title = location ?? server ?? localizedFormat("Response %lld", Int64(sections.count + 1))
            guard seen.insert(title + (server ?? "")).inserted else { continue }
            sections.append(SummarySection(title: title, detail: server, rows: rows, body: nil))
        }
        return Array(sections.prefix(24))
    }

    // MARK: - Tables of neighbors, routes, and interfaces

    private static func networkTableSummary(_ run: ToolRun) -> ResultSummary {
        switch run.tool.title {
        case "ARP Table":
            let entries = allMatches(#"^(\S+) \(([^)]+)\) at (\S+) on (\S+)(.*)$"#, in: run.output)
            if !entries.isEmpty {
                let rows = entries.map { groups -> [String] in
                    let host = groups[0] == "?" ? "" : groups[0]
                    let flags = groups[4].trimmingCharacters(in: .whitespaces)
                    return [groups[1], groups[2], groups[3], [host, flags].filter { !$0.isEmpty }.joined(separator: " · ")]
                }
                let complete = entries.filter { $0[2] != "(incomplete)" }.count
                return ResultSummary(
                    title: "IPv4 neighbors", detail: "Addresses this Mac has recently exchanged packets with.",
                    metrics: [
                        SummaryMetric(label: "Neighbors", value: String(entries.count), tone: .accent),
                        SummaryMetric(label: "Resolved", value: String(complete), detail: localizedFormat("%lld incomplete", Int64(entries.count - complete)))
                    ],
                    sections: [SummarySection(title: "Neighbor cache", detail: nil, rows: [], body: nil,
                                              table: SummaryTable(columns: ["Address", "MAC address", "Interface", "Notes"],
                                                                  rows: rows, monospaced: [0, 1]))],
                    headline: localizedFormat("%lld neighbors", Int64(entries.count))
                )
            }
        case "Gateway and Routes":
            return routesSummary(run)
        case "Interface Inventory":
            let rows = interfaceRows(run.output)
            if !rows.isEmpty {
                let active = rows.filter { $0[1] == "active" }.count
                return ResultSummary(
                    title: "Network interfaces", detail: "Every interface macOS reports, with its addresses and link status.",
                    metrics: [
                        SummaryMetric(label: "Interfaces", value: String(rows.count), tone: .accent),
                        SummaryMetric(label: "Active", value: String(active), tone: active > 0 ? .positive : .warning)
                    ],
                    sections: [SummarySection(title: "Interfaces", detail: nil, rows: [], body: nil,
                                              table: SummaryTable(columns: ["Interface", "Status", "IPv4", "IPv6", "MAC address", "MTU"],
                                                                  rows: rows, monospaced: [0, 2, 3, 4], statusColumn: 1))],
                    headline: localizedFormat("%lld interfaces", Int64(rows.count))
                )
            }
        default:
            break
        }
        let tables = columnTables(in: run.output)
        if !tables.isEmpty {
            let count = tables.reduce(0) { $0 + $1.table.rows.count }
            return ResultSummary(
                title: "Network entries", detail: "Active entries reported by macOS.",
                metrics: [SummaryMetric(label: "Entries", value: String(count), tone: .accent)],
                sections: tables.map { SummarySection(title: $0.title, detail: nil, rows: [], body: nil, table: $0.table, badge: localizedFormat("%lld rows", Int64($0.table.rows.count))) },
                headline: localizedFormat("%lld entries", Int64(count))
            )
        }
        let lines = usefulLines(run.output)
        return ResultSummary(
            title: "Network entries", detail: "Active entries reported by macOS and local discovery tools.",
            metrics: [SummaryMetric(label: "Lines", value: String(lines.count))],
            sections: excerptSections(run.output, title: run.tool.title)
        )
    }

    private static func routesSummary(_ run: ToolRun) -> ResultSummary {
        let parts = run.output.components(separatedBy: "Routing table")
        let defaultRows = keyValueRows(parts.first ?? "", limit: 12)
        var sections: [SummarySection] = []
        if !defaultRows.isEmpty {
            sections.append(SummarySection(title: "Default route", detail: nil, rows: defaultRows, body: nil))
        }
        let tables = columnTables(in: parts.dropFirst().joined(separator: "Routing table"))
        sections += tables.map { SummarySection(title: $0.title, detail: nil, rows: [], body: nil, table: $0.table, badge: localizedFormat("%lld routes", Int64($0.table.rows.count))) }
        let gateway = defaultRows.first { $0.label.caseInsensitiveCompare("gateway") == .orderedSame }?.value
        let interface = defaultRows.first { $0.label.caseInsensitiveCompare("interface") == .orderedSame }?.value
        let routeCount = tables.reduce(0) { $0 + $1.table.rows.count }
        return ResultSummary(
            title: "Gateway and routing table", detail: "The default route and every IPv4 and IPv6 route macOS knows about.",
            metrics: [
                gateway.map { SummaryMetric(label: "Gateway", value: $0, tone: .accent) },
                interface.map { SummaryMetric(label: "Interface", value: $0) },
                SummaryMetric(label: "Routes", value: String(routeCount))
            ].compactMap { $0 },
            sections: sections.isEmpty ? excerptSections(run.output, title: "Routing table") : sections,
            headline: gateway.map { localizedFormat("gateway %@", $0) }
        )
    }

    /// One table row per `ifconfig -a` block: name, status, IPv4, IPv6, MAC, and MTU.
    private static func interfaceRows(_ output: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String]?
        func finish() { if let current { rows.append(current) } }
        for line in output.components(separatedBy: .newlines) {
            if let groups = firstMatch(#"^([A-Za-z0-9_.-]+): flags=\d+<[^>]*> mtu (\d+)"#, in: line) {
                finish()
                current = [groups[0], "", "", "", "", groups[1]]
            } else if current != nil {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let groups = firstMatch(#"^inet (\S+)"#, in: trimmed), current?[2].isEmpty == true {
                    current?[2] = groups[0]
                } else if let groups = firstMatch(#"^inet6 (\S+)"#, in: trimmed), current?[3].isEmpty == true {
                    current?[3] = groups[0].components(separatedBy: "%").first ?? groups[0]
                } else if let groups = firstMatch(#"^ether (\S+)"#, in: trimmed) {
                    current?[4] = groups[0]
                } else if let groups = firstMatch(#"^status: (\S+)"#, in: trimmed) {
                    current?[1] = groups[0]
                }
            }
        }
        finish()
        return rows.map { row in
            var row = row
            if row[1].isEmpty { row[1] = row[2].isEmpty && row[3].isEmpty ? "no address" : "configured" }
            return row
        }
    }

    /// Whitespace-aligned tables introduced by a header line of column names.
    private static func columnTables(in output: String) -> [(title: String, table: SummaryTable)] {
        var tables: [(String, SummaryTable)] = []
        var columns: [String] = []
        var rows: [[String]] = []
        var title = "Entries"
        func finish() {
            if !columns.isEmpty, !rows.isEmpty { tables.append((title, SummaryTable(columns: columns, rows: rows, monospaced: Set(0..<columns.count)))) }
            columns = []; rows = []
        }
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            let isHeader = tokens.count >= 2 && tokens.allSatisfy { $0.first?.isLetter == true && !$0.contains(".") && !$0.contains(":") }
            if isHeader, tokens.contains(where: { ["Destination", "Neighbor", "Interface", "Proto", "Address"].contains($0) }) {
                finish()
                columns = tokens
            } else if line.hasSuffix(":") && tokens.count == 1 {
                finish()
                title = String(line.dropLast())
            } else if !columns.isEmpty, !tokens.isEmpty {
                var cells = Array(tokens.prefix(columns.count - 1))
                cells.append(tokens.dropFirst(columns.count - 1).joined(separator: " "))
                while cells.count < columns.count { cells.append("") }
                rows.append(cells)
            }
        }
        finish()
        return tables
    }

    // MARK: - Configuration

    private static func configurationSummary(_ run: ToolRun) -> ResultSummary {
        switch run.tool.title {
        case "DNS Configuration":
            let sections = resolverSections(run.output)
            if !sections.isEmpty {
                let primary = sections.first?.rows.first { $0.label.lowercased().hasPrefix("nameserver") }?.value
                let search = sections.first?.rows.first { $0.label.lowercased().hasPrefix("search domain") }?.value
                return ResultSummary(
                    title: "DNS resolvers in use", detail: "Resolvers and search domains macOS is currently using, in priority order.",
                    metrics: [
                        SummaryMetric(label: "Resolvers", value: String(sections.count), tone: .accent),
                        primary.map { SummaryMetric(label: "Primary nameserver", value: $0) },
                        search.map { SummaryMetric(label: "Search domain", value: $0) }
                    ].compactMap { $0 },
                    sections: sections,
                    headline: primary.map { localizedFormat("primary %@", $0) }
                )
            }
        case "DHCP Lease":
            let rows = keyValueRows(run.output, separators: "=:", limit: 48)
            if !rows.isEmpty {
                func value(_ key: String) -> String? {
                    rows.first { $0.label.lowercased().hasPrefix(key.replacingOccurrences(of: "_", with: " ")) }?
                        .value.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                }
                let lease = value("lease_time").flatMap { text -> String? in
                    guard let hex = text.split(separator: " ").first, let seconds = Int(hex.dropFirst(2), radix: 16) else { return nil }
                    return formatDuration(seconds)
                }
                return ResultSummary(
                    title: "DHCP lease", detail: "The active interface's lease and the options its DHCP server supplied.",
                    metrics: [
                        value("yiaddr").map { SummaryMetric(label: "Assigned address", value: $0, tone: .accent) },
                        value("server_identifier").map { SummaryMetric(label: "DHCP server", value: $0) },
                        value("router").map { SummaryMetric(label: "Router", value: $0) },
                        lease.map { SummaryMetric(label: "Lease time", value: $0) }
                    ].compactMap { $0 },
                    sections: [SummarySection(title: "Lease details", detail: nil, rows: rows, body: nil)],
                    headline: value("yiaddr")
                )
            }
        case "Wi-Fi Diagnostics":
            let sections = indentedSections(run.output)
            if !sections.isEmpty {
                return ResultSummary(
                    title: "Wi-Fi status", detail: "Link details for this Mac and the access points macOS can currently see.",
                    metrics: [SummaryMetric(label: "Sections", value: String(sections.count))],
                    sections: sections
                )
            }
        case "Network Quality":
            let sections = parsedSections(run.output)
            let rows = sections.flatMap(\.rows)
            func metric(_ key: String, _ label: String) -> SummaryMetric? {
                rows.first { $0.label.localizedCaseInsensitiveContains(key) }.map {
                    let value = label == "Responsiveness" ? $0.value.components(separatedBy: " (").first ?? $0.value : $0.value
                    return SummaryMetric(label: label, value: value, tone: .accent, usesCompactValueStyle: true)
                }
            }
            if !rows.isEmpty {
                return ResultSummary(
                    title: "Connection quality", detail: "Measured capacity and responsiveness of the current connection.",
                    metrics: [metric("downlink capacity", "Download"), metric("uplink capacity", "Upload"),
                              metric("responsiveness", "Responsiveness")].compactMap { $0 },
                    sections: sections
                )
            }
        default:
            break
        }
        let sections = parsedSections(run.output)
        let rows = keyValueRows(run.output, limit: 36)
        return ResultSummary(
            title: "System network configuration",
            detail: localizedFormat("Values reported by macOS for %@.", run.tool.localizedTitle.lowercased()),
            metrics: [SummaryMetric(label: "Details", value: String(max(rows.count, usefulLines(run.output).count)))],
            sections: !sections.isEmpty ? sections : rows.isEmpty ? excerptSections(run.output, title: "Configuration")
                : [SummarySection(title: "Configuration", detail: nil, rows: rows, body: nil)]
        )
    }

    /// `scutil --dns` output as one section per resolver; scoped resolvers are labelled.
    private static func resolverSections(_ output: String) -> [SummarySection] {
        var sections: [SummarySection] = []
        var scoped = false
        var title: String?
        var body: [String] = []
        func finish() {
            guard let current = title else { return }
            let rows = keyValueRows(body.joined(separator: "\n"), limit: 24)
            if !rows.isEmpty { sections.append(SummarySection(title: current, detail: nil, rows: rows, body: nil, badge: scoped ? "scoped" : nil)) }
            body = []
        }
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("DNS configuration") {
                finish(); title = nil
                scoped = line.localizedCaseInsensitiveContains("scoped")
            } else if let groups = firstMatch(#"^resolver #(\d+)$"#, in: line) {
                finish()
                title = localizedFormat("Resolver %@", groups[0])
            } else if title != nil {
                body.append(line)
            }
        }
        finish()
        return sections
    }

    /// Nested `system_profiler` text: a line that only names a heading opens a new section.
    private static func indentedSections(_ output: String) -> [SummarySection] {
        var sections: [SummarySection] = []
        var title = "Overview"
        var body: [String] = []
        func finish() {
            let rows = keyValueRows(body.joined(separator: "\n"), limit: 24)
            if !rows.isEmpty { sections.append(SummarySection(title: title, detail: nil, rows: rows, body: nil)) }
            body = []
        }
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasSuffix(":") && !line.dropLast().contains(":") {
                finish()
                title = String(line.dropLast())
            } else {
                body.append(line)
            }
        }
        finish()
        return Array(sections.prefix(24))
    }

    // MARK: - Registration

    private static func registrationSummary(_ run: ToolRun) -> ResultSummary {
        if let json = jsonRows(run.output), !json.isEmpty {
            let status = json.first { $0.label.localizedCaseInsensitiveContains("status") }?.value
            return ResultSummary(
                title: "Registration and routing data",
                detail: localizedFormat("Structured registry response for %@.", run.target.nilIfEmpty ?? localized("the selected resource")),
                metrics: [
                    SummaryMetric(label: "Fields", value: String(json.count)),
                    status.map { SummaryMetric(label: "Status", value: $0.components(separatedBy: "\n").first ?? $0, tone: .accent) }
                ].compactMap { $0 },
                sections: [SummarySection(title: "Registry record", detail: nil, rows: Array(json.prefix(40)), body: nil)]
            )
        }
        if let table = pipeTable(in: run.output) {
            return ResultSummary(
                title: "Origin AS and routed prefix", detail: localizedFormat("Routing registry data for %@.", run.target.nilIfEmpty ?? localized("the address")),
                metrics: table.rows.first.map { row in
                    zip(table.columns, row).prefix(3).map { SummaryMetric(label: $0.0, value: $0.1, tone: .accent) }
                } ?? [],
                sections: [SummarySection(title: "Routing record", detail: nil, rows: [], body: nil, table: table, badge: nil)]
            )
        }
        let preferred = [
            "domain name", "domain", "registrar", "registrar name", "organisation", "organization",
            "orgname", "netname", "country", "creation date", "created", "registry expiry date",
            "expiration date", "updated date", "name server", "nserver", "refer", "whois", "origin",
            "as name", "asname", "route", "status"
        ]
        let rows = keyValueRows(run.output, preferred: preferred, limit: 30)
        let registrar = rows.first { $0.label.lowercased().hasPrefix("registrar") }?.value
        let expiry = rows.first { $0.label.lowercased().contains("expir") }?.value.components(separatedBy: "\n").first
        return ResultSummary(
            title: "Registration and routing data",
            detail: rows.isEmpty ? "The registry returned an unstructured response; its useful lines are shown below." : "Key fields from the registry response.",
            metrics: [
                SummaryMetric(label: "Fields", value: String(rows.count)),
                registrar.map { SummaryMetric(label: "Registrar", value: $0.components(separatedBy: "\n").first ?? $0, tone: .accent) },
                expiry.map { SummaryMetric(label: "Expires", value: $0) }
            ].compactMap { $0 },
            sections: rows.isEmpty ? excerptSections(run.output, title: "Registry response")
                : [SummarySection(title: "Record", detail: nil, rows: rows, body: nil)]
        )
    }

    /// Cymru-style `A | B | C` tables.
    private static func pipeTable(in output: String) -> SummaryTable? {
        let lines = usefulLines(output).filter { $0.contains(" | ") }
        guard lines.count >= 2 else { return nil }
        let split: (String) -> [String] = { $0.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
        let columns = split(lines[0])
        let rows = lines.dropFirst().map(split).filter { $0.count == columns.count }
        guard !rows.isEmpty else { return nil }
        return SummaryTable(columns: columns, rows: rows, monospaced: [0, 1, 2])
    }

    // MARK: - DNS

    private static func dnsSummary(_ run: ToolRun) -> ResultSummary {
        if let json = jsonRows(run.output), !json.isEmpty {
            return ResultSummary(
                title: "DNS response", detail: "Structured resolver response.",
                metrics: [SummaryMetric(label: "Fields", value: String(json.count))],
                sections: [SummarySection(title: "Response", detail: nil, rows: Array(json.prefix(32)), body: nil)]
            )
        }
        if run.tool.title == "DNS Propagation" {
            let answers = headedBlocks(run.output).map { ($0.title, $0.lines.sorted()) }
            if !answers.isEmpty {
                let distinct = Set(answers.map { $0.1.joined(separator: ",") })
                let consistent = distinct.count == 1 && !(answers.first?.1.isEmpty ?? true)
                let table = SummaryTable(columns: ["Resolver", "Answers"],
                                         rows: answers.map { [$0.0, $0.1.isEmpty ? "no answer" : $0.1.joined(separator: ", ")] },
                                         monospaced: [0, 1], statusColumn: 1)
                return ResultSummary(
                    title: consistent ? "Resolvers agree" : "Resolvers differ",
                    detail: consistent ? "Every public resolver returned the same DNS answers." : "Public resolvers returned different answers; a change may still be propagating.",
                    metrics: [
                        SummaryMetric(label: "Resolvers", value: String(answers.count)),
                        SummaryMetric(label: "Consistent", value: consistent ? "Yes" : "No", tone: consistent ? .positive : .warning)
                    ],
                    sections: [SummarySection(title: "Answers by resolver", detail: nil, rows: [], body: nil, table: table)],
                    headline: consistent ? "consistent" : "differs"
                )
            }
        }
        let records = dnsRecords(run.output).map(presentedDNSRecord)
        if !records.isEmpty {
            let types = uniqueOrdered(records.map { $0[2] })
            let validation = validationMetric(run.output)
            return ResultSummary(
                title: "DNS records", detail: localizedFormat("Answers returned for %@.", run.target.nilIfEmpty ?? localized("the selected target")),
                metrics: [
                    SummaryMetric(label: "Records", value: String(records.count), tone: .accent),
                    SummaryMetric(label: "Types", value: types.joined(separator: ", ")),
                    validation
                ].compactMap { $0 },
                sections: [SummarySection(title: "Answers", detail: nil, rows: [], body: nil,
                                          table: SummaryTable(columns: ["Name", "TTL", "Type", "Value"], rows: records, monospaced: [0, 1, 3]))],
                headline: localizedFormat("%lld records", Int64(records.count))
            )
        }
        let lines = usefulLines(run.output).filter { !$0.hasPrefix(";") }
        if !lines.isEmpty, lines.allSatisfy({ !$0.contains(" ") || $0.hasPrefix("\"") }) {
            // `+short` style answers: one value per line.
            return ResultSummary(
                title: "DNS answers", detail: localizedFormat("Values returned for %@.", run.target.nilIfEmpty ?? localized("the selected target")),
                metrics: [SummaryMetric(label: "Answers", value: String(lines.count), tone: .accent)],
                sections: [SummarySection(title: "Answers", detail: nil,
                                          rows: lines.enumerated().map { SummaryRow(label: localizedFormat("Answer %lld", Int64($0.offset + 1)), value: $0.element) }, body: nil)],
                headline: localizedFormat("%lld answers", Int64(lines.count))
            )
        }
        let validation = validationMetric(run.output)
        return ResultSummary(
            title: lines.isEmpty ? "No DNS records found" : "DNS response",
            detail: lines.isEmpty ? "The resolver returned no matching answers." : "Resolver output grouped for quick review.",
            metrics: [SummaryMetric(label: "Lines", value: String(lines.count)), validation].compactMap { $0 },
            sections: excerptSections(run.output, title: "Resolver response")
        )
    }

    /// Resolver blocks in order, keeping headings whose answer block is empty. Decorated headings
    /// remain supported so older captured output can still be interpreted.
    private static func headedBlocks(_ output: String) -> [(title: String, lines: [String])] {
        var result: [(title: String, lines: [String])] = []
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let heading = reportSectionHeading(line) {
                result.append((heading, []))
            } else if !line.isEmpty, !result.isEmpty {
                result[result.count - 1].lines.append(line)
            }
        }
        return result
    }

    /// DNSSEC helper and `dig +dnssec` outcomes as a colour-coded metric.
    private static func validationMetric(_ output: String) -> SummaryMetric? {
        let lower = output.lowercased()
        if lower.contains("; fully validated") { return SummaryMetric(label: "DNSSEC", value: "Validated", tone: .positive) }
        if lower.contains("; unsigned answer") { return SummaryMetric(label: "DNSSEC", value: "Unsigned", tone: .warning) }
        if lower.contains("resolution failed") || lower.contains("; validation failed") {
            return SummaryMetric(label: "DNSSEC", value: "Failed", tone: .negative)
        }
        if let flags = capture(#"flags:([^;\n]*)"#, in: output), flags.split(separator: " ").contains("ad") {
            return SummaryMetric(label: "DNSSEC", value: "Authenticated", tone: .positive)
        }
        return nil
    }

    /// macOS ships an older dig that prints SVCB and HTTPS records as generic wire data.
    /// Decode the standard parameters so the overview still shows useful connection hints.
    private static func presentedDNSRecord(_ row: [String]) -> [String] {
        guard row.count == 4, row[2] == "TYPE64" || row[2] == "TYPE65",
              let decoded = decodeServiceBinding(row[3]) else { return row }
        return [row[0], row[1], row[2] == "TYPE65" ? "HTTPS" : "SVCB", decoded]
    }

    private static func decodeServiceBinding(_ value: String) -> String? {
        let parts = value.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 3, parts[0] == "\\#" else { return nil }
        let hex = parts.dropFirst(2).joined()
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<end], radix: 16) else { return nil }
            bytes.append(byte)
            index = end
        }
        guard bytes.count >= 3 else { return nil }
        var offset = 0
        func readUInt16() -> UInt16? {
            guard offset + 2 <= bytes.count else { return nil }
            defer { offset += 2 }
            return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        }
        guard let priority = readUInt16() else { return nil }
        var labels: [String] = []
        while offset < bytes.count {
            let length = Int(bytes[offset]); offset += 1
            if length == 0 { break }
            guard length <= 63, offset + length <= bytes.count,
                  let label = String(bytes: bytes[offset..<(offset + length)], encoding: .utf8) else { return nil }
            labels.append(label); offset += length
        }
        let target = labels.isEmpty ? "." : labels.joined(separator: ".") + "."
        var parameters: [String] = []
        while offset < bytes.count {
            guard let key = readUInt16(), let lengthValue = readUInt16() else { return nil }
            let length = Int(lengthValue)
            guard offset + length <= bytes.count else { return nil }
            let data = Array(bytes[offset..<(offset + length)]); offset += length
            parameters.append(serviceBindingParameter(key: key, data: data))
        }
        return ([String(priority), target] + parameters).joined(separator: " ")
    }

    private static func serviceBindingParameter(key: UInt16, data: [UInt8]) -> String {
        switch key {
        case 0:
            var names: [String] = []
            for offset in stride(from: 0, to: data.count - data.count % 2, by: 2) {
                let value = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
                names.append(serviceBindingKeyName(value))
            }
            return "mandatory=" + names.joined(separator: ",")
        case 1:
            var protocols: [String] = []
            var offset = 0
            while offset < data.count {
                let length = Int(data[offset]); offset += 1
                guard offset + length <= data.count else { break }
                protocols.append(String(bytes: data[offset..<(offset + length)], encoding: .utf8) ?? "?")
                offset += length
            }
            return "alpn=" + protocols.joined(separator: ",")
        case 2:
            return "no-default-alpn"
        case 3 where data.count == 2:
            return "port=" + String(UInt16(data[0]) << 8 | UInt16(data[1]))
        case 4 where data.count.isMultiple(of: 4):
            let addresses = stride(from: 0, to: data.count, by: 4).map {
                data[$0..<($0 + 4)].map(String.init).joined(separator: ".")
            }
            return "ipv4hint=" + addresses.joined(separator: ",")
        case 5:
            return "ech=" + Data(data).base64EncodedString()
        case 6 where data.count.isMultiple(of: 16):
            let addresses = stride(from: 0, to: data.count, by: 16).map { start in
                stride(from: start, to: start + 16, by: 2).map {
                    String(format: "%x", UInt16(data[$0]) << 8 | UInt16(data[$0 + 1]))
                }.joined(separator: ":")
            }
            return "ipv6hint=" + addresses.joined(separator: ",")
        case 7:
            return "dohpath=" + (String(bytes: data, encoding: .utf8) ?? Data(data).base64EncodedString())
        default:
            return serviceBindingKeyName(key) + "=" + data.map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func serviceBindingKeyName(_ key: UInt16) -> String {
        switch key {
        case 0: return "mandatory"
        case 1: return "alpn"
        case 2: return "no-default-alpn"
        case 3: return "port"
        case 4: return "ipv4hint"
        case 5: return "ech"
        case 6: return "ipv6hint"
        case 7: return "dohpath"
        default: return "key\(key)"
        }
    }

    private static func dnsRecords(_ output: String) -> [[String]] {
        var result: [[String]] = []
        for line in usefulLines(output) where !line.hasPrefix(";") && !line.hasPrefix("%") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 5, Int(parts[1]) != nil, parts[2] == "IN" else { continue }
            result.append([String(parts[0]), String(parts[1]), String(parts[3]), parts.dropFirst(4).joined(separator: " ")])
        }
        return Array(result.prefix(200))
    }

    // MARK: - Latency

    private static func latencySummary(_ run: ToolRun) -> ResultSummary {
        switch run.tool.title {
        case "Traceroute":
            return tracerouteSummary(run)
        case "NTP Offset":
            if let groups = firstMatch(#"^([+-][0-9.]+) \+/- ([0-9.]+) (\S+)(?: (\S+))?"#, in: run.output),
               let offset = Double(groups[0]), let uncertainty = Double(groups[1]) {
                let magnitude = abs(offset)
                return ResultSummary(
                    title: "Clock offset", detail: localizedFormat("Difference between this Mac's clock and %@.", groups[2]),
                    metrics: [
                        SummaryMetric(label: "Offset", value: formatNumber(offset * 1000), unit: "ms",
                                      tone: magnitude < 0.1 ? .positive : magnitude < 1 ? .warning : .negative),
                        SummaryMetric(label: "Uncertainty", value: "±\(formatNumber(uncertainty * 1000))", unit: "ms"),
                        SummaryMetric(label: "Server", value: groups[3].isEmpty ? groups[2] : groups[3])
                    ],
                    sections: excerptSections(run.output, title: "Measurement"),
                    headline: localizedFormat("%@ ms", formatNumber(offset * 1000))
                )
            }
        default:
            break
        }
        return pingSummary(run.output, title: "Connection timing", tool: run.tool.title)
    }

    static func pingSummary(_ output: String, title: String, tool: String) -> ResultSummary {
        var metrics: [SummaryMetric] = []
        if let loss = capture(#"([0-9.]+)% packet loss"#, in: output), let value = Double(loss) {
            metrics.append(SummaryMetric(label: "Packet loss", value: "\(loss)%",
                                         tone: value == 0 ? .positive : value < 100 ? .warning : .negative))
        }
        if let values = capture(#"(?:round-trip|rtt).*?=\s*([0-9.]+)/([0-9.]+)/([0-9.]+)"#, groups: 3, in: output) {
            metrics += [
                SummaryMetric(label: "Minimum", value: values[0], unit: "ms"),
                SummaryMetric(label: "Average", value: "\(values[1]) ms", tone: .accent),
                SummaryMetric(label: "Maximum", value: values[2], unit: "ms")
            ]
        }
        let replies = allMatches(#"^(\d+) bytes from ([^:]+): icmp_seq=(\d+) ttl=(\d+) time=([0-9.]+) ms$"#, in: output)
        var sections: [SummarySection] = []
        if !replies.isEmpty {
            sections.append(SummarySection(
                title: "Replies", detail: nil, rows: [], body: nil,
                table: SummaryTable(columns: ["Sequence", "From", "TTL", "Time"],
                                    rows: replies.map { [$0[2], $0[1], $0[3], "\($0[4]) ms"] }, monospaced: [1, 3]),
                badge: localizedFormat("%lld received", Int64(replies.count))
            ))
        }
        if let stats = usefulLines(output).first(where: { $0.contains("packets transmitted") }) {
            sections.append(SummarySection(title: "Statistics", detail: nil, rows: [], body: stats + "\n" +
                (usefulLines(output).first { $0.contains("round-trip") || $0.contains("rtt") } ?? "")))
        }
        let loss = metrics.first { $0.label == "Packet loss" }
        return ResultSummary(
            title: loss?.tone == .negative ? "Target did not reply" : title,
            detail: localizedFormat("Reachability and round-trip timing for %@.", localized(tool == "Ping" ? "four ICMP echo requests" : "the target")),
            metrics: metrics,
            sections: sections.isEmpty ? excerptSections(output, title: "Measurement") : sections,
            headline: metrics.first { $0.label == "Average" }?.value
        )
    }

    private static func tracerouteSummary(_ run: ToolRun) -> ResultSummary {
        var rows: [[String]] = []
        var timeouts = 0
        for line in run.output.components(separatedBy: .newlines) {
            guard let groups = firstMatch(#"^[ \t]*(\d+)[ \t]+(.*)$"#, in: line) else { continue }
            let rest = groups[1].trimmingCharacters(in: .whitespaces)
            let times = allMatches(#"([0-9.]+) ms"#, in: rest).map { "\($0[0]) ms" }
            if let host = firstMatch(#"^(\S+) \(([^)]+)\)"#, in: rest) {
                rows.append([groups[0], host[0], host[1], times.joined(separator: " · ")])
            } else if rest.replacingOccurrences(of: " ", with: "").allSatisfy({ $0 == "*" }) {
                timeouts += 1
                rows.append([groups[0], "no reply", "", "timed out"])
            } else {
                rows.append([groups[0], rest, "", times.joined(separator: " · ")])
            }
        }
        guard !rows.isEmpty else {
            return ResultSummary(title: "Route to target", detail: "Latency, reachability, and path measurements.",
                                 metrics: [], sections: excerptSections(run.output, title: "Trace"))
        }
        let last = rows.last?[3].components(separatedBy: " · ").first ?? ""
        let unreached = run.output.contains("did not answer within")
        return ResultSummary(
            title: unreached ? "Destination not reached" : "Route to target",
            detail: "Each router on the path; the round-trip time is measured at the destination.",
            metrics: [
                SummaryMetric(label: "Hops", value: String(rows.count), tone: .accent),
                SummaryMetric(label: "Destination", value: unreached ? "Not reached" : "Reached", detail: last.isEmpty ? nil : last,
                              tone: unreached ? .warning : .positive),
                SummaryMetric(label: "Timeouts", value: String(timeouts), tone: timeouts == 0 ? .positive : .warning)
            ],
            sections: [SummarySection(title: "Hops", detail: nil, rows: [], body: nil,
                                      table: SummaryTable(columns: ["Hop", "Host", "Address", "Round trip"], rows: rows,
                                                          monospaced: [0, 2, 3], statusColumn: 3))],
            headline: localizedFormat("%lld hops", Int64(rows.count))
        )
    }

    // MARK: - HTTP and TLS

    private static func httpSummary(_ run: ToolRun) -> ResultSummary {
        if let json = jsonRows(run.output), !json.isEmpty {
            let status = json.first { $0.label.caseInsensitiveCompare("status") == .orderedSame }?.value
            return ResultSummary(title: "Web policy status", detail: "Structured response from the web service.",
                                 metrics: [SummaryMetric(label: "Fields", value: String(json.count)),
                                           status.map { SummaryMetric(label: "Status", value: $0, tone: .accent) }].compactMap { $0 },
                                 sections: [SummarySection(title: "Response", detail: nil, rows: json, body: nil)])
        }
        let normalized = run.output.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var sections: [SummarySection] = []
        for (index, block) in blocks.enumerated() {
            let lines = usefulLines(block)
            let status = lines.first(where: { $0.hasPrefix("HTTP/") })
            let rows = keyValueRows(block, limit: 40)
            let code = status.flatMap { capture(#"HTTP/\S+\s+(\d+)"#, in: $0) }
            sections.append(SummarySection(title: status ?? localizedFormat("Response %lld", Int64(index + 1)), detail: nil, rows: rows,
                                           body: rows.isEmpty ? lines.joined(separator: "\n") : nil,
                                           badge: rows.isEmpty ? nil : localizedFormat("%lld headers", Int64(rows.count)),
                                           tone: code.map(httpTone) ?? .neutral))
        }
        let status = capture(#"Status:\s*(\d+)"#, in: run.output)
            ?? capture(#"HTTP/\S+\s+(\d+)"#, in: run.output)
        let finalStatus = sections.last.flatMap { capture(#"HTTP/\S+\s+(\d+)"#, in: $0.title) }
        return ResultSummary(
            title: "HTTP response", detail: "Status, protocol, redirects, and returned headers.",
            metrics: [
                status.map { SummaryMetric(label: "Status", value: $0, tone: httpTone($0)) },
                finalStatus.flatMap { sections.count > 1 ? SummaryMetric(label: "Final status", value: $0, tone: httpTone($0)) : nil },
                SummaryMetric(label: "Responses", value: String(max(sections.count, 1)),
                              detail: sections.count > 1 ? localizedFormat("%lld redirects", Int64(sections.count - 1)) : nil)
            ].compactMap { $0 },
            sections: sections.isEmpty ? excerptSections(run.output, title: "Response") : sections,
            headline: status.map { "HTTP \($0)" }
        )
    }

    private static func httpTone(_ status: String) -> SummaryTone {
        guard let code = Int(status) else { return .neutral }
        switch code {
        case 200..<300: return .positive
        case 300..<400: return .accent
        case 400..<500: return .warning
        default: return .negative
        }
    }

    private static func tlsSummary(_ run: ToolRun) -> ResultSummary {
        var rows = keyValueRows(run.output, limit: 36)
        let equalsKeys = ["subject", "issuer", "serial", "notbefore", "notafter", "sha256 fingerprint"]
        for line in run.output.components(separatedBy: .newlines) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard equalsKeys.contains(key.lowercased()), !value.isEmpty else { continue }
            let row = SummaryRow(label: key.titleCased, value: value)
            if !rows.contains(where: { $0.label == row.label && $0.value == row.value }) { rows.append(row) }
        }
        func row(_ label: String) -> SummaryRow? {
            rows.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }
        }
        var metrics: [SummaryMetric] = []
        if let protocolRow = row("Protocol Version") ?? row("Protocol") {
            metrics.append(SummaryMetric(label: "Protocol", value: protocolRow.value.components(separatedBy: "\n").first ?? protocolRow.value,
                                         tone: protocolRow.value.contains("1.3") ? .positive : protocolRow.value.contains("1.2") ? .accent : .warning))
        }
        if let cipher = row("Ciphersuite") ?? row("Cipher") {
            metrics.append(SummaryMetric(label: "Ciphersuite", value: cipher.value.components(separatedBy: "\n").first ?? cipher.value))
        }
        if let verification = row("Verification") ?? row("Verify Return Code") {
            let ok = verification.value.hasPrefix("OK") || verification.value.hasPrefix("0 (ok)")
            metrics.append(SummaryMetric(label: "Verification", value: verification.value, tone: ok ? .positive : .negative))
        }
        if let expiry = row("Notafter") {
            let days = daysUntil(expiry.value)
            metrics.append(SummaryMetric(label: "Certificate expires", value: expiry.value,
                                         detail: days.map(expiryDetail), tone: days.map(expiryTone) ?? .neutral))
        }
        rows = rows.map { row in
            var row = row
            if row.label.caseInsensitiveCompare("verification") == .orderedSame || row.label.caseInsensitiveCompare("verify return code") == .orderedSame {
                row.tone = row.value.hasPrefix("OK") || row.value.hasPrefix("0 (ok)") ? .positive : .negative
            }
            return row
        }
        return ResultSummary(
            title: "TLS connection",
            detail: "Negotiated protocol, cipher, certificate identity, and verification status.",
            metrics: metrics.isEmpty ? [SummaryMetric(label: "Details", value: String(rows.count))] : metrics,
            sections: rows.isEmpty ? excerptSections(run.output, title: "Handshake response")
                : [SummarySection(title: "Security details", detail: nil, rows: rows, body: nil)],
            headline: metrics.first { $0.label == "Protocol" }?.value
        )
    }

    private static func daysUntil(_ text: String) -> Int? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
        guard let date = formatter.date(from: text.replacingOccurrences(of: "  ", with: " ")) else { return nil }
        return Int((date.timeIntervalSinceNow / 86_400).rounded(.down))
    }

    private static func expiryDetail(_ days: Int) -> String {
        days < 0
            ? localizedFormat("expired %lld days ago", Int64(-days))
            : days == 0 ? localized("expires today") : localizedFormat("in %lld days", Int64(days))
    }

    private static func expiryTone(_ days: Int) -> SummaryTone {
        days < 0 ? .negative : days < 30 ? .warning : .positive
    }

    // MARK: - Ports

    private static func portSummary(_ run: ToolRun) -> ResultSummary {
        switch run.tool.title {
        case "TCP Port Check":
            if let groups = firstMatch(#"Connection to (\S+) port (\d+) \[([^\]]+)\] succeeded"#, in: run.output) {
                return ResultSummary(
                    title: localizedFormat("Port %@ is open", groups[1]), detail: localizedFormat("%@ accepted a TCP connection.", groups[0]),
                    metrics: [
                        SummaryMetric(label: "State", value: "Open", tone: .positive),
                        SummaryMetric(label: "Port", value: groups[1], detail: groups[2]),
                        SummaryMetric(label: "Host", value: groups[0])
                    ],
                    sections: [SummarySection(title: "Connection", detail: nil,
                                              rows: [SummaryRow(label: "Host", value: groups[0]), SummaryRow(label: "Port", value: groups[1]),
                                                     SummaryRow(label: "Service", value: groups[2]), SummaryRow(label: "Result", value: "Connection succeeded", tone: .positive)],
                                              body: nil)],
                    headline: "open"
                )
            }
        case "Common Port Scan":
            let open = allMatches(#"^(\d+)\t(\S+)\t(.+)$"#, in: run.output)
            if !open.isEmpty || run.output.contains("Open ports:") {
                let count = capture(#"Open ports: (\d+)"#, in: run.output) ?? String(open.count)
                let table = SummaryTable(columns: ["Port", "State", "Service"], rows: open.map { [$0[0], $0[1], $0[2]] },
                                         monospaced: [0], statusColumn: 1)
                return ResultSummary(
                    title: open.isEmpty ? "No common ports are open" : localizedFormat("%@ open ports", count),
                    detail: "The 25 most common TCP ports were probed with a one-second timeout.",
                    metrics: [
                        SummaryMetric(label: "Open ports", value: count, tone: open.isEmpty ? .warning : .positive),
                        SummaryMetric(label: "Probed", value: "25")
                    ],
                    sections: open.isEmpty ? excerptSections(run.output, title: "Scan")
                        : [SummarySection(title: "Open ports", detail: nil, rows: [], body: nil, table: table, badge: localizedFormat("%lld open", Int64(open.count)))],
                    headline: localizedFormat("%@ open", count)
                )
            }
        case "SSH Host Keys":
            let keys = allMatches(#"^(\d+) (\S+) (.*) \((\w+)\)$"#, in: run.output)
            if !keys.isEmpty {
                return ResultSummary(
                    title: "SSH host keys", detail: "Fingerprints the server presented, to compare against a known-hosts entry.",
                    metrics: [SummaryMetric(label: "Keys", value: String(keys.count), tone: .accent),
                              SummaryMetric(label: "Types", value: uniqueOrdered(keys.map { $0[3] }).joined(separator: ", "))],
                    sections: [SummarySection(title: "Host keys", detail: nil, rows: [], body: nil,
                                              table: SummaryTable(columns: ["Type", "Bits", "Fingerprint", "Host"],
                                                                  rows: keys.map { [$0[3], $0[0], $0[1], $0[2]] }, monospaced: [2]))],
                    headline: localizedFormat("%lld keys", Int64(keys.count))
                )
            }
        default:
            break
        }
        let lines = usefulLines(run.output)
        return ResultSummary(title: "Service reachability", detail: "Reachable ports, services, and host-key details.",
                             metrics: [SummaryMetric(label: "Lines", value: String(lines.count))],
                             sections: excerptSections(run.output, title: "Output"))
    }

    // MARK: - Documents, utilities, and public address

    private static func documentSummary(_ run: ToolRun) -> ResultSummary {
        let lines = usefulLines(run.output)
        if run.tool.title == "Certificate Transparency" {
            let names = uniqueOrdered(lines).sorted()
            return ResultSummary(
                title: "Names in certificate logs", detail: "Hostnames that appeared in public certificates for this domain.",
                metrics: [SummaryMetric(label: "Names", value: String(names.count), tone: .accent)],
                sections: [SummarySection(title: "Certificate names", detail: nil, rows: [], body: nil,
                                          table: SummaryTable(columns: ["Name"], rows: names.prefix(400).map { [$0] }, monospaced: [0]),
                                          omittedLines: max(0, names.count - 400))],
                headline: localizedFormat("%lld names", Int64(names.count))
            )
        }
        let rows = keyValueRows(run.output, limit: 40)
        let section = bodySection(title: "Content", lines: lines)
        return ResultSummary(
            title: run.tool.title, detail: "Content returned by the target, ready to inspect or copy.",
            metrics: [SummaryMetric(label: "Lines", value: String(lines.count)),
                      rows.isEmpty ? nil : SummaryMetric(label: "Directives", value: String(rows.count))].compactMap { $0 },
            sections: [section]
        )
    }

    private static func utilitySummary(_ run: ToolRun) -> ResultSummary {
        let rows = keyValueRows(run.output, limit: 36)
        let lines = usefulLines(run.output)
        switch run.tool.title {
        case "IP Range Expander" where rows.isEmpty:
            return ResultSummary(
                title: localizedFormat("%lld addresses", Int64(lines.count)), detail: "Every address in the requested range, one per line.",
                metrics: [SummaryMetric(label: "Addresses", value: String(lines.count), tone: .accent),
                          SummaryMetric(label: "First", value: lines.first ?? "—"), SummaryMetric(label: "Last", value: lines.last ?? "—")],
                sections: [bodySection(title: "Addresses", lines: lines)],
                headline: localizedFormat("%lld addresses", Int64(lines.count))
            )
        case "MAC Formatter" where rows.isEmpty:
            return ResultSummary(
                title: "Formatted address", detail: "The MAC address in canonical uppercase, colon-separated form.",
                metrics: [SummaryMetric(label: "MAC address", value: lines.first ?? "—", tone: .accent)],
                sections: [SummarySection(title: "Result", detail: nil, rows: [SummaryRow(label: "Formatted", value: lines.first ?? "—")], body: nil)],
                headline: lines.first
            )
        default:
            break
        }
        return ResultSummary(
            title: "Calculated result", detail: localizedFormat("Values produced by %@.", run.tool.localizedTitle),
            metrics: rows.prefix(4).map { SummaryMetric(label: $0.label, value: $0.value, tone: .accent) }.nilIfEmpty
                ?? [SummaryMetric(label: "Lines", value: String(lines.count))],
            sections: rows.isEmpty ? [bodySection(title: "Result", lines: lines)]
                : [SummarySection(title: "Details", detail: nil, rows: rows, body: nil)]
        )
    }

    private static func publicAddressSummary(_ run: ToolRun) -> ResultSummary {
        if let json = jsonRows(run.output), !json.isEmpty {
            func value(_ key: String) -> String? { json.first { $0.label.caseInsensitiveCompare(key) == .orderedSame }?.value }
            let location = [value("city"), value("region"), value("country")].compactMap { $0 }.joined(separator: ", ")
            return ResultSummary(
                title: value("ip").map { localizedFormat("Address details for %@", $0) } ?? "Address details",
                detail: "Public address and network ownership details.",
                metrics: [
                    value("ip").map { SummaryMetric(label: "IP address", value: $0, tone: .accent) },
                    location.isEmpty ? nil : SummaryMetric(label: "Location", value: location),
                    value("org").map { SummaryMetric(label: "Network", value: $0) },
                    value("hostname").map { SummaryMetric(label: "Hostname", value: $0) }
                ].compactMap { $0 },
                sections: [SummarySection(title: "Details", detail: nil, rows: json, body: nil)],
                headline: value("ip")
            )
        }
        let lines = usefulLines(run.output)
        if lines.count == 1, let address = lines.first {
            return ResultSummary(
                title: "Your public address", detail: "The address the internet sees for this connection.",
                metrics: [SummaryMetric(label: address.contains(":") ? "Public IPv6" : "Public IPv4", value: address, tone: .accent)],
                sections: [SummarySection(title: "Address", detail: nil, rows: [SummaryRow(label: "Public IP", value: address)], body: nil)],
                headline: address
            )
        }
        let rows = keyValueRows(run.output, limit: 36)
        return ResultSummary(
            title: "Address details", detail: "Public address and network ownership details.",
            metrics: [SummaryMetric(label: rows.isEmpty ? "Lines" : "Fields", value: String(rows.isEmpty ? lines.count : rows.count))],
            sections: rows.isEmpty ? excerptSections(run.output, title: "Result")
                : [SummarySection(title: "Details", detail: nil, rows: rows, body: nil)]
        )
    }

    // MARK: - Composite reports

    private static func reportSummary(_ run: ToolRun) -> ResultSummary {
        if run.tool.title == "DNS Zone Discovery" { return dnsZoneDiscoverySummary(run) }
        let sections = parsedSections(run.output)
        guard !sections.isEmpty else {
            return ResultSummary(title: "Report overview", detail: "Results are grouped by each completed network check.",
                                 metrics: [SummaryMetric(label: "Checks", value: "1")],
                                 sections: excerptSections(run.output, title: run.tool.title))
        }
        var metrics = reportMetrics(run.output, sections: sections)
        metrics.append(SummaryMetric(label: "Checks", value: String(sections.count)))
        let subject = capture(#"^(?:Network report|Site report|Mail TLS report) for (\S+)$"#, in: run.output)
        return ResultSummary(
            title: subject.map { localizedFormat("Report for %@", $0) } ?? "Report overview",
            detail: "Results are grouped by each completed network check.",
            metrics: Array(metrics.prefix(5)),
            sections: sections,
            headline: metrics.first.map { "\($0.label.lowercased()) \($0.value)" }
        )
    }

    /// DNS enumeration is complete only when the helper received an AXFR. Every probing-based
    /// result is deliberately labelled partial, even when it found many records.
    private static func dnsZoneDiscoverySummary(_ run: ToolRun) -> ResultSummary {
        var seen: Set<String> = []
        let records = dnsRecords(run.output).filter { seen.insert($0.joined(separator: "\t")).inserted }
        let names = Set(records.map { $0[0].trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        let complete = run.output.contains("Completeness: Complete")
        let mode = capture(#"^Mode: (\S+)$"#, in: run.output) ?? (run.optionEnabled ? "Deep" : "Quick")
        let method = capture(#"^Method: (.+)$"#, in: run.output)
        var sections = parsedSections(run.output)
        if sections.isEmpty { sections = excerptSections(run.output, title: "Discovery output") }
        return ResultSummary(
            title: complete
                ? localizedFormat("Complete DNS zone for %@", run.target)
                : localizedFormat("DNS records discovered for %@", run.target),
            detail: complete
                ? "The authoritative server allowed a complete AXFR zone transfer."
                : "Public DNS probing found useful records, but custom names may still be hidden.",
            metrics: [
                SummaryMetric(label: "Coverage", value: complete ? "Complete" : "Partial", tone: complete ? .positive : .warning),
                SummaryMetric(label: "Records", value: String(records.count), tone: .accent),
                SummaryMetric(label: "Names", value: String(names.count)),
                SummaryMetric(label: "Mode", value: mode, detail: method)
            ],
            sections: sections,
            headline: complete ? localized("complete zone") : localizedFormat("%lld records · partial", Int64(records.count))
        )
    }

    /// Headline numbers pulled from whichever checks a composite report ran.
    private static func reportMetrics(_ output: String, sections: [SummarySection]) -> [SummaryMetric] {
        var metrics: [SummaryMetric] = []
        let rows = sections.flatMap(\.rows)
        // Rows from labelled sub-blocks carry a "Default · " style prefix, so match the suffix too.
        func first(_ keys: [String]) -> String? {
            for key in keys {
                if let row = rows.first(where: {
                    $0.label.caseInsensitiveCompare(key) == .orderedSame || $0.label.lowercased().hasSuffix(" · \(key.lowercased())")
                }) {
                    return row.value.components(separatedBy: "\n").first
                }
            }
            return nil
        }
        if let address = first(["Resolved address", "Primary mail server"]) {
            metrics.append(SummaryMetric(label: address.contains(" ") ? "Server" : "Address", value: address, tone: .accent))
        }
        if let network = first(["Network"]) { metrics.append(SummaryMetric(label: "Network", value: network)) }
        if let country = first(["Country"]) { metrics.append(SummaryMetric(label: "Country", value: country)) }
        if let status = capture(#"HTTP/\S+\s+(\d+)"#, in: output) {
            metrics.append(SummaryMetric(label: "HTTP status", value: status, tone: httpTone(status)))
        }
        if let protocolValue = first(["Protocol"]) {
            metrics.append(SummaryMetric(label: "TLS", value: protocolValue, tone: protocolValue.contains("1.3") ? .positive : .accent))
        }
        if let expiry = first(["Notafter"]), let days = daysUntil(expiry) {
            metrics.append(SummaryMetric(label: "Certificate", value: expiryDetail(days), tone: expiryTone(days)))
        }
        if let loss = capture(#"([0-9.]+)% packet loss"#, in: output), let value = Double(loss) {
            metrics.append(SummaryMetric(label: "Packet loss", value: "\(loss)%", tone: value == 0 ? .positive : value < 100 ? .warning : .negative))
        }
        if let open = capture(#"Open ports: (\d+)"#, in: output) {
            metrics.append(SummaryMetric(label: "Open ports", value: open, tone: .accent))
        }
        return metrics
    }

    /// Splits plain report labels, legacy decorated labels, and discovery headings into sections,
    /// choosing the best presentation for each block.
    private static func parsedSections(_ output: String) -> [SummarySection] {
        var result: [SummarySection] = []
        var title = "Overview"
        var body: [String] = []
        func appendSection() {
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            result.append(bestSection(title: title.capitalizedTitle, text: text))
        }
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let heading = reportSectionHeading(line) {
                appendSection()
                title = heading
                body = []
            } else if !line.allSatisfy({ $0 == "-" }) {
                body.append(raw)
            }
        }
        appendSection()
        // A one-line overview such as "Site report for example.org" only repeats the headline.
        if result.count > 1, result[0].title == "Overview", result[0].table == nil, result[0].rows.isEmpty,
           let body = result[0].body, !body.contains("\n") {
            result.removeFirst()
        }
        return Array(result.prefix(24))
    }

    /// Recognizes only labels owned by Netmin, plus the previous decorated format. Resolver labels
    /// return just the address because that becomes the resolver column in the summary table.
    private static func reportSectionHeading(_ line: String) -> String? {
        if line.hasPrefix("===") && line.hasSuffix("===") && line.count > 6 {
            return line.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
        }
        if line.hasPrefix("|") && line.hasSuffix("|") && line.count > 2 {
            return line.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
        }
        if reportSectionLabels.contains(line) { return line }
        if ["Fast local discovery", "Devices", "Common TCP services", "Bonjour services"]
            .contains(where: { line.hasPrefix($0) }) {
            return line
        }
        guard line.hasPrefix("Resolver ") else { return nil }
        let resolver = line.dropFirst("Resolver ".count).trimmingCharacters(in: .whitespaces)
        return resolver.isEmpty ? nil : resolver
    }

    /// Picks a table, rows, metrics, or plain text for one block of a composite report.
    private static func bestSection(title: String, text: String) -> SummarySection {
        let lines = usefulLines(text)
        let records = dnsRecords(text)
        if records.count >= 1, records.count * 2 >= lines.filter({ !$0.hasPrefix(";") }).count {
            return SummarySection(title: title, detail: nil, rows: [], body: nil,
                                  table: SummaryTable(columns: ["Name", "TTL", "Type", "Value"], rows: records, monospaced: [0, 1, 3]),
                                  badge: localizedFormat("%lld records", Int64(records.count)))
        }
        if text.contains("packets transmitted") {
            let ping = pingSummary(text, title: title, tool: "Ping")
            let loss = ping.metrics.first { $0.label == "Packet loss" }
            return SummarySection(title: title, detail: ping.metrics.map(metricText).joined(separator: " · "),
                                  rows: [], body: nil, table: ping.sections.first?.table,
                                  badge: loss.map { $0.tone == .positive ? localized("reachable") : localizedFormat("loss %@", $0.value) },
                                  tone: loss?.tone ?? .neutral)
        }
        let hops = allMatches(#"^[ \t]*(\d+)[ \t]+(\S+) \(([^)]+)\)[ \t]*(.*)$"#, in: text)
        if hops.count >= 2 {
            let rows = hops.map { [$0[0], $0[1], $0[2], allMatches(#"([0-9.]+) ms"#, in: $0[3]).map { "\($0[0]) ms" }.joined(separator: " · ")] }
            return SummarySection(title: title, detail: nil, rows: [], body: nil,
                                  table: SummaryTable(columns: ["Hop", "Host", "Address", "Round trip"], rows: rows, monospaced: [0, 2, 3]),
                                  badge: localizedFormat("%lld hops", Int64(rows.count)))
        }
        let reachability = allMatches(#"^(SSH|HTTP|HTTPS)[ \t]+(\S+)[ \t]+(open.*|closed.*|timed out.*|.*timed out)$"#, in: text)
        if !reachability.isEmpty {
            return SummarySection(title: title, detail: nil, rows: reachability.map {
                SummaryRow(label: "\($0[0]) · \($0[1])", value: $0[2], tone: $0[2].hasPrefix("open") ? .positive : .negative)
            }, body: nil, badge: localizedFormat("%lld of %lld open", Int64(reachability.filter { $0[2].hasPrefix("open") }.count), Int64(reachability.count)))
        }
        let scan = allMatches(#"^(\d+)\t(\S+)\t(.+)$"#, in: text)
        if !scan.isEmpty {
            return SummarySection(title: title, detail: nil, rows: [], body: nil,
                                  table: SummaryTable(columns: ["Port", "State", "Service"], rows: scan.map { [$0[0], $0[1], $0[2]] }, monospaced: [0], statusColumn: 1),
                                  badge: localizedFormat("%lld open", Int64(scan.count)))
        }
        let subsections = labelledSubsections(text)
        if subsections.count >= 2 {
            let rows = subsections.flatMap { sub in sub.rows.map { SummaryRow(label: "\(localized(sub.title)) · \(localized($0.label))", value: $0.value, tone: $0.tone) } }
            return SummarySection(title: title, detail: nil, rows: rows, body: nil, badge: localizedFormat("%lld checks", Int64(subsections.count)))
        }
        let rows = keyValueRows(text, limit: 40).map { row -> SummaryRow in
            var row = row
            if row.label.caseInsensitiveCompare("verification") == .orderedSame || row.label.caseInsensitiveCompare("verify return code") == .orderedSame {
                row.tone = row.value.hasPrefix("OK") || row.value.hasPrefix("0 (ok)") ? .positive : .negative
            } else if row.label.caseInsensitiveCompare("tcp") == .orderedSame {
                row.tone = row.value.hasPrefix("open") ? .positive : .negative
            }
            return row
        }
        if !rows.isEmpty, rows.count * 3 >= lines.count {
            return SummarySection(title: title, detail: nil, rows: rows, body: nil)
        }
        return bodySection(title: title, lines: lines)
    }

    /// Blocks such as "Default" / "TLS 1.2" / "TLS 1.3" whose values are indented beneath a label.
    private static func labelledSubsections(_ text: String) -> [(title: String, rows: [SummaryRow])] {
        var result: [(String, [SummaryRow])] = []
        var title: String?
        var body: [String] = []
        func finish() {
            if let title {
                let rows = keyValueRows(body.joined(separator: "\n"), limit: 12).map { row -> SummaryRow in
                    var row = row
                    if row.label.caseInsensitiveCompare("verify return code") == .orderedSame { row.tone = row.value.hasPrefix("0 (ok)") ? .positive : .negative }
                    if row.label.caseInsensitiveCompare("tcp") == .orderedSame { row.tone = row.value.hasPrefix("open") ? .positive : .negative }
                    return row
                }
                result.append((title, rows))
            }
            body = []
        }
        for raw in text.components(separatedBy: .newlines) {
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let indented = raw.hasPrefix(" ") || raw.hasPrefix("\t")
            if !indented, !raw.contains(":"), raw.count < 40 {
                finish()
                title = raw.trimmingCharacters(in: .whitespaces)
            } else if !indented, let groups = firstMatch(#"^([A-Za-z0-9 .-]+?)[ \t]{2,}(\S+:\d+)$"#, in: raw) {
                finish()
                title = "\(groups[0]) · \(groups[1])"
            } else if title != nil {
                body.append(raw)
            } else {
                return []
            }
        }
        finish()
        return result.filter { !$0.1.isEmpty }
    }

    // MARK: - Shared parsing helpers

    private static func metricText(_ metric: SummaryMetric) -> String {
        var text = "\(localized(metric.label)) \(localized(metric.value))"
        if let unit = metric.unit { text += " \(localized(unit))" }
        return text
    }

    private static func bodySection(title: String, lines: [String], limit: Int = 400) -> SummarySection {
        SummarySection(title: title, detail: nil, rows: [], body: lines.prefix(limit).joined(separator: "\n"),
                       omittedLines: max(0, lines.count - limit))
    }

    private static func excerptSections(_ output: String, title: String) -> [SummarySection] {
        let lines = usefulLines(output)
        return lines.isEmpty ? [] : [bodySection(title: title, lines: lines)]
    }

    /// Lines that follow a heading up to the next blank line.
    private static func block(after heading: String, in output: String) -> [String] {
        var collecting = false
        var lines: [String] = []
        for raw in output.components(separatedBy: .newlines) {
            if raw.hasPrefix(heading) { collecting = true; continue }
            guard collecting else { continue }
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { break }
            lines.append(raw)
        }
        return lines
    }

    private static func keyValueRows(_ output: String, preferred: [String] = [], separators: String = ":", limit: Int) -> [SummaryRow] {
        var values: [String: [String]] = [:]
        var order: [String] = []
        let separatorSet = CharacterSet(charactersIn: separators)
        for line in output.components(separatedBy: .newlines) {
            guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("%"),
                  let separator = keyValueSeparator(in: line, separators: separatorSet) else { continue }
            let rawKey = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let key = rawKey.lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.count <= 70, !value.isEmpty, value.count < 2_000, !key.contains("  ") else { continue }
            if values[key] == nil { order.append(key) }
            if !(values[key] ?? []).contains(value) { values[key, default: []].append(value) }
        }
        let selected = preferred.isEmpty ? order : preferred.filter { values[$0] != nil }
        return selected.prefix(limit).compactMap { key in
            guard let found = values[key], !found.isEmpty else { return nil }
            return SummaryRow(label: key.titleCased, value: found.prefix(8).joined(separator: "\n"))
        }
    }

    /// The first configured separator, or an earlier `=` when the line is an OpenSSL-style
    /// `notAfter=Nov 18 23:59:59 2026 GMT` pair whose value happens to contain colons.
    private static func keyValueSeparator(in line: String, separators: CharacterSet) -> String.Index? {
        let configured = line.unicodeScalars.firstIndex { separators.contains($0) }
        guard let equals = line.firstIndex(of: "=") else { return configured }
        if let configured, configured <= equals { return configured }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let keyIsSimple = !key.isEmpty && key.count <= 40 && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || $0 == "_" || $0 == "-" || $0 == "." }
        return keyIsSimple ? equals : configured
    }

    private static func jsonRows(_ output: String) -> [SummaryRow]? {
        guard let data = output.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var rows: [SummaryRow] = []
        func flatten(_ value: Any, path: String, depth: Int) {
            guard rows.count < 60, depth < 5 else { return }
            if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() {
                    guard let child = dictionary[key] else { continue }
                    flatten(child, path: path.isEmpty ? key : "\(path).\(key)", depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                if array.allSatisfy({ $0 is String || $0 is NSNumber }) {
                    rows.append(SummaryRow(label: path.titleCased, value: array.prefix(8).map { String(describing: $0) }.joined(separator: "\n")))
                } else {
                    for (index, item) in array.prefix(8).enumerated() { flatten(item, path: "\(path)[\(index)]", depth: depth + 1) }
                }
            } else if !(value is NSNull) {
                rows.append(SummaryRow(label: path.titleCased, value: String(describing: value)))
            }
        }
        flatten(object, path: "", depth: 0)
        return rows
    }

    private static func usefulLines(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func uniqueOrdered(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func hasCompleteWHOISRecord(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("registrar:") &&
            (lower.contains("name server:") || lower.contains("nserver:")) &&
            (lower.contains("registry expiry date:") || lower.contains("expiration date:"))
    }

    private static func firstValue(named names: [String], in output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            if names.contains(key) {
                let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func expression(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
    }

    private static func capture(_ pattern: String, groups: Int = 1, in text: String) -> [String]? {
        guard let expression = expression(pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1...groups).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        capture(pattern, groups: 1, in: text)?.first
    }

    /// Every capture group of the first match, with unmatched groups as empty strings.
    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        allMatches(pattern, in: text).first
    }

    /// Capture groups for every match in the text, one array per match.
    private static func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let expression = expression(pattern) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private static func failureDetail(from output: String, status: Int32) -> String {
        if output.localizedCaseInsensitiveContains("maximum"),
           output.localizedCaseInsensitiveContains("redirects followed") {
            return "The app followed the redirects, but the website sent this file back to the same URL repeatedly. No file was returned."
        }
        let lines = usefulLines(output)
        return lines.suffix(3).joined(separator: "\n").nilIfEmpty
            ?? localizedFormat("The process exited with status %lld before returning details. Check that the required command is installed and the target is reachable.", Int64(status))
    }

    static func formatMilliseconds(_ value: Double) -> String {
        "\(formatNumber(value)) ms"
    }

    static func formatNumber(_ value: Double) -> String {
        value == value.rounded() && abs(value) >= 10 ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func formatDuration(_ seconds: Int) -> String {
        func quantity(_ count: Int, singular: String, plural: String) -> String {
            count == 1 ? localizedFormat(singular, Int64(count)) : localizedFormat(plural, Int64(count))
        }
        if seconds % 86_400 == 0 { return quantity(seconds / 86_400, singular: "%lld day", plural: "%lld days") }
        if seconds % 3_600 == 0 { return quantity(seconds / 3_600, singular: "%lld hour", plural: "%lld hours") }
        if seconds % 60 == 0 { return quantity(seconds / 60, singular: "%lld minute", plural: "%lld minutes") }
        return quantity(seconds, singular: "%lld second", plural: "%lld seconds")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
    var titleCased: String {
        replacingOccurrences(of: ".", with: " · ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
    /// Keeps acronyms such as DNS or TLS while lowering shouted headings like "TCP REACHABILITY".
    var capitalizedTitle: String {
        let acronyms: Set<String> = [
            "DNS", "TLS", "TCP", "UDP", "HTTP", "HTTPS", "MX", "STARTTLS", "OCSP", "IP", "ASN", "SSH", "SMTP",
            "IMAP", "IMAPS", "POP3", "POP3S", "SMTPS", "SSL", "DHCP", "ARP", "NTP", "RDAP", "WHOIS", "CAA",
            "TLSA", "SRV", "TXT", "AAAA", "NS", "SOA", "MAC", "URL", "BGP", "RPKI", "CIDR", "SSDP", "UPNP",
            "SMB", "DANE", "DKIM", "SPF", "DMARC", "BIMI", "HSTS", "AS", "CC", "SUMMARY"
        ]
        let shouted = self == uppercased() && rangeOfCharacter(from: .letters) != nil
        guard shouted else { return self }
        let words = split(separator: " ").enumerated().map { index, word -> String in
            let text = String(word)
            if text == "IPV4" { return "IPv4" }
            if text == "IPV6" { return "IPv6" }
            if acronyms.contains(text) && text != "SUMMARY" { return text }
            return index == 0 ? text.capitalized : text.lowercased()
        }
        return words.joined(separator: " ")
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}
