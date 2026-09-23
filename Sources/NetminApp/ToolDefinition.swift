import Foundation

enum SummaryKind: String, CaseIterable {
    case report
    case publicAddress
    case discovery
    case networkTable
    case configuration
    case registration
    case dnsRecords
    case latency
    case tls
    case http
    case port
    case document
    case utility
}

/// Stable visual categories keep related tools recognizable without tying meaning to color alone.
enum ToolVisualCategory {
    case dns
    case reports
    case localNetwork
    case routing
    case mail
    case webAndPorts
    case utilities
}

struct ToolDefinition: Identifiable, Hashable {
    let id: String
    let group: String
    let title: String
    let command: String
    let placeholder: String
    let resolverPlaceholder: String?
    let summary: String
    let optionLabel: String?
    let optionArgument: String?
    let optionDefault: Bool
    let progressMessage: String
    let allowsEmptyTarget: Bool
    let targetPolicy: TargetPolicy
    let secondaryInputPolicy: TargetPolicy

    var localizedGroup: String { localized(group) }
    var localizedTitle: String { localized(title) }
    var localizedPlaceholder: String { localized(placeholder) }
    var localizedResolverPlaceholder: String? { resolverPlaceholder.map(localized) }
    var localizedSummary: String { localized(summary) }
    var localizedOptionLabel: String? { optionLabel.map(localized) }
    var localizedProgressMessage: String { localized(progressMessage) }

    init(
        id: String,
        group: String,
        title: String,
        command: String,
        placeholder: String,
        resolverPlaceholder: String?,
        summary: String,
        optionLabel: String?,
        optionArgument: String?,
        optionDefault: Bool,
        progressMessage: String,
        allowsEmptyTarget: Bool = false,
        targetPolicy: TargetPolicy = .any,
        secondaryInputPolicy: TargetPolicy = .hostOrIP
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.command = command
        self.placeholder = placeholder
        self.resolverPlaceholder = resolverPlaceholder
        self.summary = summary
        self.optionLabel = optionLabel
        self.optionArgument = optionArgument
        self.optionDefault = optionDefault
        self.progressMessage = progressMessage
        self.allowsEmptyTarget = allowsEmptyTarget
        self.targetPolicy = targetPolicy
        self.secondaryInputPolicy = secondaryInputPolicy
    }

    var usesTarget: Bool {
        command.contains("$1") || command.contains("${1")
    }

    var usesResolver: Bool {
        command.contains("$2") || command.contains("${2")
    }

    /// DNS queries can optionally route the same lookup through a user-selected server.
    var supportsCustomResolver: Bool {
        if title == "DNSSEC Validation" || title == "DANE Validation" { return true }
        guard command.contains("/usr/bin/dig"), title != "DNS Propagation" else { return false }
        return group == "DNS" || title == "Reverse DNS"
    }

    var requiresTarget: Bool {
        usesTarget && !allowsEmptyTarget
    }

    var secondaryInputLabel: String {
        title == "RPKI Validation" ? "IP prefix" : "Resolver"
    }

    /// Returns the detected kind when the value fits this tool, or an invalid kind with the
    /// tool's expected input when a well-formed value belongs to the wrong category.
    func validatedTargetKind(_ value: String) -> TargetKind {
        targetPolicy.validatedKind(value, expected: localizedPlaceholder)
    }

    func validatedSecondaryInputKind(_ value: String) -> TargetKind {
        let expected = localizedResolverPlaceholder ?? localized("DNS server")
        return secondaryInputPolicy.validatedKind(value, expected: expected)
    }

    /// The sweep has its own form that previews and selects the networks to scan.
    var isLocalDeviceSweep: Bool {
        title == "Local Device Sweep"
    }

    /// Bound commands that depend on remote hosts so a silent endpoint cannot leave the UI
    /// running forever. Reports and discovery tools receive more time for their many probes.
    var maximumDuration: TimeInterval {
        if title == "Local Device Sweep" { return 300 }
        if title == "Network Quality" { return 120 }
        if title == "DNS Zone Transfer" { return 90 }
        if group == "Reports" || title == "DNS Zone Discovery" || title == "Mail TLS Report" {
            return 120
        }
        return 45
    }

    /// Choose the icon tint from the catalog section. Network Lookup remains blue because it is the
    /// app's general lookup entry rather than a generated report.
    var visualCategory: ToolVisualCategory {
        if title == "Network Lookup" { return .dns }
        switch group {
        case "Reports": return .reports
        case "Local Network": return .localNetwork
        case "IP, Routing and Registration": return .routing
        case "DNS": return .dns
        case "Mail": return .mail
        case "TLS, Web and Ports": return .webAndPorts
        default: return .utilities
        }
    }

    var symbolName: String {
        let lower = title.lowercased()
        if lower == "network lookup" { return "globe" }
        if lower.contains("site report") { return "doc.text.magnifyingglass" }
        if lower.contains("network report") { return "chart.bar.xaxis" }
        if lower.contains("public ip") || lower.contains("ip information") || lower.contains("geolocation") { return "mappin.and.ellipse" }
        if lower.contains("device sweep") { return "dot.radiowaves.left.and.right" }
        if lower.contains("bonjour") { return "waveform.path.ecg" }
        if lower.contains("ssdp") || lower.contains("upnp") { return "square.stack.3d.up" }
        if lower.contains("windows name") { return "pc" }
        if lower.contains("arp table") { return "tablecells" }
        if lower.contains("neighbors") { return "list.bullet" }
        if lower.contains("interface") { return "rectangle.connected.to.line.below" }
        if lower.contains("wi-fi") { return "wifi" }
        if lower.contains("dhcp") { return "arrow.down.doc" }
        if lower.contains("gateway") { return "arrow.triangle.branch" }
        if lower.contains("traceroute") { return "point.topleft.down.to.point.bottomright.curvepath" }
        if lower.contains("ping") { return "waveform" }
        if lower.contains("whois") { return "shield" }
        if lower.contains("rdap") { return "list.bullet.rectangle" }
        if lower.contains("asn") || lower.contains("bgp") || lower.contains("rpki") { return "point.3.connected.trianglepath.dotted" }
        if lower.contains("reverse dns") { return "arrow.uturn.backward" }
        if lower.contains("mail") || lower.contains("smtp") || lower.contains("dane") { return "envelope" }
        if lower.contains("tls") || lower.contains("certificate") || lower.contains("hsts") { return "lock.shield" }
        if lower.contains("http") || lower.contains(".txt") { return "doc.text" }
        if lower.contains("port") || lower.contains("ssh") { return "network.badge.shield.half.filled" }
        if lower.contains("dnssec") { return "checkmark.shield" }
        if lower.contains("dns") { return "server.rack" }
        if lower.contains("ntp") { return "clock" }
        if lower.contains("network quality") { return "gauge.with.dots.needle.67percent" }
        if group == "Utilities" { return "wrench.and.screwdriver" }
        return "network"
    }

    var summaryKind: SummaryKind {
        if Self.reportTools.contains(title) { return .report }
        if Self.publicAddressTools.contains(title) { return .publicAddress }
        if Self.discoveryTools.contains(title) { return .discovery }
        if Self.networkTableTools.contains(title) { return .networkTable }
        if Self.configurationTools.contains(title) { return .configuration }
        if Self.registrationTools.contains(title) { return .registration }
        if Self.dnsTools.contains(title) { return .dnsRecords }
        if Self.latencyTools.contains(title) { return .latency }
        if Self.tlsTools.contains(title) { return .tls }
        if Self.httpTools.contains(title) { return .http }
        if Self.portTools.contains(title) { return .port }
        if Self.documentTools.contains(title) { return .document }
        return .utility
    }

    var hasDedicatedSummary: Bool {
        Self.knownTools.contains(title)
    }

    private static let reportTools: Set<String> = [
        "Network Lookup", "Site Report", "My Network Report", "DNS Zone Discovery", "Mail TLS Report"
    ]
    private static let publicAddressTools: Set<String> = ["My Public IP", "IP Information"]
    private static let discoveryTools: Set<String> = [
        "Local Device Sweep", "Bonjour Services", "SSDP/UPnP Discovery", "Windows Name Discovery"
    ]
    private static let networkTableTools: Set<String> = [
        "ARP Table", "IPv6 Neighbors", "Gateway and Routes", "Interface Inventory"
    ]
    private static let configurationTools: Set<String> = [
        "DNS Configuration", "DHCP Lease", "Wi-Fi Diagnostics", "Network Quality"
    ]
    private static let registrationTools: Set<String> = [
        "RDAP IP", "RDAP Domain", "WHOIS", "ASN and BGP Lookup", "RPKI Validation"
    ]
    private static let dnsTools: Set<String> = [
        "Reverse DNS", "DNS A", "DNS AAAA", "DNS CNAME", "DNS NS", "DNS SOA", "DNS TXT",
        "DNS CAA", "DNS SRV", "DNS NAPTR", "DNS LOC", "DNS HTTPS", "DNS SVCB", "DNS TLSA", "DNS Zone Transfer",
        "DNS Propagation", "DNS over HTTPS", "DNSSEC DS", "DNSSEC DNSKEY", "DNSSEC Check",
        "DNSSEC Validation", "DNSSEC Chain Trace", "DNS NSEC Walk Check", "DNS Trace", "Mail MX",
        "Mail SPF", "Mail DMARC", "Mail DKIM", "Mail BIMI", "Mail MTA-STS", "Mail TLS-RPT",
        "Mail Autodiscover SRV", "Mail Submission SRV", "Mail IMAPS SRV", "DANE Validation",
    ]
    private static let latencyTools: Set<String> = ["Ping", "Traceroute", "NTP Offset"]
    private static let tlsTools: Set<String> = [
        "SMTP STARTTLS", "TLS Certificate", "TLS Handshake", "TLS Service Handshake",
        "TLS Certificate Chain", "TLS 1.2 Handshake", "TLS 1.3 Handshake", "DNS over TLS Endpoint"
    ]
    private static let httpTools: Set<String> = [
        "HTTP Headers", "HTTP Security Headers", "HTTP Protocol", "HSTS Preload Status"
    ]
    private static let portTools: Set<String> = ["TCP Port Check", "Common Port Scan", "SSH Host Keys"]
    private static let documentTools: Set<String> = ["Security.txt", "Robots.txt", "Certificate Transparency"]
    private static let utilityTools: Set<String> = [
        "CIDR Calculator", "IP Range Expander", "Punycode Converter", "MAC Formatter"
    ]
    private static let knownTools = reportTools.union(publicAddressTools).union(discoveryTools)
        .union(networkTableTools).union(configurationTools).union(registrationTools).union(dnsTools)
        .union(latencyTools).union(tlsTools).union(httpTools).union(portTools).union(documentTools)
        .union(utilityTools)
}

struct ToolGroup: Identifiable {
    let name: String
    let tools: [ToolDefinition]
    var id: String { name }
}
