import Foundation

/// What the target field detects as the user types, so the form can show a matching icon,
/// a short explanation, and refuse clearly malformed addresses before the command runs.
enum TargetKind: Equatable {
    case empty
    case ipv4
    case ipv6
    case cidr(addresses: UInt64)
    case url
    case hostPort
    case mac
    case service
    case asn
    case domain
    case text
    case invalid(String)

    var isInvalid: Bool {
        if case .invalid = self { return true }
        return false
    }

    var symbolName: String {
        switch self {
        case .empty: return "magnifyingglass"
        case .ipv4, .ipv6: return "number"
        case .cidr: return "square.grid.3x3"
        case .url: return "link"
        case .hostPort: return "arrow.left.arrow.right"
        case .mac: return "barcode"
        case .service: return "antenna.radiowaves.left.and.right"
        case .asn: return "point.3.connected.trianglepath.dotted"
        case .domain: return "globe"
        case .text: return "text.cursor"
        case .invalid: return "exclamationmark.circle"
        }
    }

    var description: String {
        switch self {
        case .empty: return ""
        case .ipv4: return localized("IPv4 address")
        case .ipv6: return localized("IPv6 address")
        case .cidr(let addresses): return localizedFormat("CIDR range · %@ addresses", TargetInput.formatCount(addresses))
        case .url: return "URL"
        case .hostPort: return localized("Host and port")
        case .mac: return localized("MAC address")
        case .service: return localized("DNS service name")
        case .asn: return "ASN"
        case .domain: return localized("Domain")
        case .text: return localized("Text")
        case .invalid(let reason): return reason
        }
    }
}

enum TargetPolicy: String {
    case any
    case hostOrIP = "host-or-ip"
    case dnsName = "dns-name"
    case dnsTarget = "dns-target"
    case domain
    case ip
    case ipOrPrefix = "ip-or-prefix"
    case ipPrefix = "ip-prefix"
    case ipv4CIDR = "ipv4-cidr"
    case asn
    case asnOrIP = "asn-or-ip"
    case service
    case hostPort = "host-port"
    case url
    case httpURL = "http-url"
    case mac

    func validatedKind(_ value: String, expected: String) -> TargetKind {
        let kind = TargetInput.classify(value)
        if (self == .asn || self == .asnOrIP), TargetInput.isASN(value) { return .asn }
        if kind == .empty || kind.isInvalid { return kind }
        let accepted: Bool
        switch self {
        case .any:
            accepted = true
        case .hostOrIP:
            accepted = kind == .domain || kind == .ipv4 || kind == .ipv6
        case .dnsName:
            accepted = kind == .domain || kind == .service
        case .dnsTarget:
            accepted = kind == .domain || kind == .service || kind == .ipv4 || kind == .ipv6
        case .domain:
            accepted = kind == .domain
        case .ip:
            accepted = kind == .ipv4 || kind == .ipv6
        case .ipOrPrefix:
            if case .cidr = kind { accepted = true } else { accepted = kind == .ipv4 || kind == .ipv6 }
        case .ipPrefix:
            if case .cidr = kind { accepted = true } else { accepted = false }
        case .ipv4CIDR:
            if case .cidr = kind {
                accepted = TargetInput.isIPv4(String(value.split(separator: "/", maxSplits: 1).first ?? ""))
            } else {
                accepted = false
            }
        case .asn, .asnOrIP:
            accepted = kind == .asn || (self == .asnOrIP && (kind == .ipv4 || kind == .ipv6))
        case .service:
            accepted = kind == .service
        case .hostPort:
            accepted = kind == .hostPort
        case .url:
            accepted = kind == .url
        case .httpURL:
            let scheme = URL(string: value)?.scheme?.lowercased()
            accepted = kind == .url && (scheme == "http" || scheme == "https")
        case .mac:
            accepted = kind == .mac
        }
        return accepted ? kind : .invalid(expected)
    }
}

enum TargetInput {
    static func classify(_ text: String) -> TargetKind {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .empty }
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return .invalid(localized("Targets cannot contain spaces"))
        }
        if value.contains("://") {
            return URL(string: value)?.host != nil ? .url : .invalid(localized("The URL needs a scheme and a host, e.g. https://example.com"))
        }
        if let cidr = parseCIDR(value) { return cidr }
        if isIPv4(value) { return .ipv4 }
        if value.contains(":") {
            if isIPv6(value) { return .ipv6 }
            if let port = hostPort(value) { return port }
            if isMAC(value) { return .mac }
            return .invalid(localized("Use host:port, an IPv6 address, or a MAC address"))
        }
        if isMAC(value) { return .mac }
        // Dotted forms made only of digits are attempted addresses rather than hostnames.
        if value.allSatisfy({ $0.isNumber || $0 == "." }) {
            return .invalid(localized("An IPv4 address needs four numbers from 0 to 255"))
        }
        if value.hasPrefix("_") { return .service }
        if isASN(value) { return .asn }
        if isHostname(value) { return .domain }
        return .text
    }

    static func isASN(_ value: String) -> Bool {
        let normalized = value.uppercased().hasPrefix("AS") ? String(value.dropFirst(2)) : value
        guard !normalized.isEmpty, normalized.allSatisfy(\.isNumber),
              let number = UInt64(normalized) else { return false }
        return number > 0 && number <= UInt64(UInt32.max)
    }

    static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, let number = Int(part) else { return false }
            return number >= 0 && number <= 255
        }
    }

    static func isIPv6(_ value: String) -> Bool {
        var address = in6_addr()
        return value.withCString { inet_pton(AF_INET6, $0, &address) == 1 }
    }

    /// Accepts colon, hyphen, or dot separated MAC forms as the MAC Formatter tool does.
    static func isMAC(_ value: String) -> Bool {
        let hex = value.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard hex.count == 12, hex.allSatisfy(\.isHexDigit) else { return false }
        return value.count == 12 || value.count == 17 || value.count == 14
    }

    static func parseCIDR(_ value: String) -> TargetKind? {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let address = String(parts[0])
        guard let prefix = Int(parts[1]) else { return .invalid(localized("The prefix after / must be a number")) }
        if isIPv4(address) {
            guard (0...32).contains(prefix) else { return .invalid(localized("An IPv4 prefix runs from /0 to /32")) }
            return .cidr(addresses: UInt64(1) << UInt64(32 - prefix))
        }
        if isIPv6(address) {
            guard (0...128).contains(prefix) else { return .invalid(localized("An IPv6 prefix runs from /0 to /128")) }
            let bits = 128 - prefix
            return .cidr(addresses: bits >= 64 ? UInt64.max : UInt64(1) << UInt64(bits))
        }
        return .invalid(localized("A CIDR range needs a full address before the prefix, e.g. 10.2.0.0/24"))
    }

    private static func hostPort(_ value: String) -> TargetKind? {
        if value.hasPrefix("["), let closing = value.firstIndex(of: "]") {
            let address = String(value[value.index(after: value.startIndex)..<closing])
            let suffix = value[value.index(after: closing)...]
            guard suffix.hasPrefix(":"), let port = Int(suffix.dropFirst()),
                  (1...65_535).contains(port), isIPv6(address) else { return nil }
            return .hostPort
        }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let port = Int(parts[1]), (1...65_535).contains(port) else { return nil }
        let host = String(parts[0])
        return isIPv4(host) || isHostname(host) ? .hostPort : nil
    }

    static func isHostname(_ value: String) -> Bool {
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, value.count <= 253 else { return false }
        return labels.enumerated().allSatisfy { index, label in
            // A trailing dot (an absolute name) leaves one empty final label.
            if label.isEmpty { return index == labels.count - 1 && labels.count > 1 }
            guard label.count <= 63, !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    static func formatCount(_ value: UInt64) -> String {
        if value == UInt64.max { return "2⁶⁴+" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
