import Foundation
import SystemConfiguration

/// A private IPv4 network this Mac is attached to, computed the same way the sweep helper does
/// so the form can preview exactly what a blank sweep target would scan.
struct DetectedNetwork: Identifiable, Hashable {
    let interface: String
    let address: String
    let cidr: String
    let prefix: Int
    let kind: String
    let gateway: String?
    let isPrimary: Bool

    var id: String { cidr }

    /// The sweep helper limits anything wider than a /22 to the local /24.
    var isLimitedToLocal24: Bool { prefix < 22 }

    var scannedCIDR: String {
        guard isLimitedToLocal24, let value = LocalNetworks.ipv4Value(address) else { return cidr }
        return "\(LocalNetworks.ipv4String(value & 0xFFFF_FF00))/24"
    }

    var hostCount: Int {
        let bits = isLimitedToLocal24 ? 8 : 32 - prefix
        return max(0, (1 << bits) - 2)
    }

    /// Rough wall-clock estimate: the helper pings hosts in batches of 64 with a 200 ms timeout,
    /// probes services afterwards, and browses Bonjour for four seconds.
    var estimatedSeconds: Int { LocalNetworks.estimate(hostCount: hostCount) }
}

enum LocalNetworks {
    static func estimate(hostCount: Int) -> Int {
        max(2, Int((Double(hostCount) / 254 * 6).rounded()))
    }

    static func estimate(cidr: String) -> Int? {
        guard case .cidr(let addresses) = TargetInput.classify(cidr) else { return nil }
        let bounded = min(addresses, 254)
        return estimate(hostCount: Int(bounded))
    }

    /// Every up, non-loopback interface with a private IPv4 address, deduplicated by network.
    static func detect() -> [DetectedNetwork] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        let kinds = interfaceKinds()
        let route = defaultRoute()
        var result: [DetectedNetwork] = []
        var seen: Set<String> = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let item = entry.pointee
            guard let socketAddress = item.ifa_addr, socketAddress.pointee.sa_family == UInt8(AF_INET),
                  item.ifa_flags & UInt32(IFF_UP) != 0, item.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let netmask = item.ifa_netmask else { continue }
            let address = ipv4(from: socketAddress)
            let mask = ipv4(from: netmask)
            guard isPrivate(address) else { continue }
            let prefix = mask.nonzeroBitCount
            guard prefix < 31 else { continue }
            let network = address & mask
            let cidr = "\(ipv4String(network))/\(prefix)"
            guard seen.insert(cidr).inserted else { continue }
            let name = String(cString: item.ifa_name)
            result.append(DetectedNetwork(
                interface: name,
                address: ipv4String(address),
                cidr: cidr,
                prefix: prefix,
                kind: kinds[name] ?? genericKind(for: name),
                gateway: route?.interface == name ? route?.gateway : nil,
                isPrimary: route?.interface == name
            ))
        }
        // The primary interface first, then the order macOS reported.
        return result.sorted { $0.isPrimary && !$1.isPrimary }
    }

    static func ipv4Value(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return parts[0] << 24 | parts[1] << 16 | parts[2] << 8 | parts[3]
    }

    static func ipv4String(_ value: UInt32) -> String {
        "\(value >> 24 & 255).\(value >> 16 & 255).\(value >> 8 & 255).\(value & 255)"
    }

    private static func ipv4(from address: UnsafeMutablePointer<sockaddr>) -> UInt32 {
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
    }

    private static func isPrivate(_ value: UInt32) -> Bool {
        let first = value >> 24 & 255
        let second = value >> 16 & 255
        return first == 10 || (first == 172 && (16...31).contains(second)) || (first == 192 && second == 168)
    }

    /// Localized interface names from SystemConfiguration, keyed by BSD name.
    private static func interfaceKinds() -> [String: String] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var result: [String: String] = [:]
        for interface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let type = SCNetworkInterfaceGetInterfaceType(interface) as String?
            let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            result[bsd] = type == (kSCNetworkInterfaceTypeIEEE80211 as String) ? "Wi-Fi" : display ?? genericKind(for: bsd)
        }
        return result
    }

    private static func genericKind(for name: String) -> String {
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") { return "VPN tunnel" }
        if name.hasPrefix("bridge") { return "Virtual bridge" }
        if name.hasPrefix("vmnet") || name.hasPrefix("vnic") { return "Virtual machine network" }
        if name.hasPrefix("en") { return "Ethernet" }
        return "Interface"
    }

    /// The default IPv4 route from the dynamic store, without spawning a process.
    private static func defaultRoute() -> (interface: String, gateway: String)? {
        guard let store = SCDynamicStoreCreate(nil, "Netmin" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let interface = global["PrimaryInterface"] as? String else { return nil }
        return (interface, global["Router"] as? String ?? "")
    }
}
