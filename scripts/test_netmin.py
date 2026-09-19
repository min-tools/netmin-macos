#!/usr/bin/env python3
"""Check the Netmin catalog, command templates and result interpretation offline."""
from pathlib import Path
import os
import subprocess
import tempfile

from build import ROOT, swift_compiler

APP = ROOT / 'Sources/NetminApp'
CATALOG = APP / 'Resources/tools.tsv'

fixture = r'''
import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let tools = try ToolCatalog.load(from: URL(fileURLWithPath: CommandLine.arguments[1]))
check(tools.count == 84, "Expected 84 Netmin tools")
check(Set(tools.map(\.id)).count == tools.count, "Tool IDs must be unique")
check(!tools.contains { $0.command.contains("/opt/homebrew") || $0.command.contains("/usr/local") },
      "Catalog commands must not require Homebrew")
check(tools.allSatisfy(\.hasDedicatedSummary), "Every catalog tool needs a dedicated summary strategy")
check(tools.filter(\.usesTarget).allSatisfy { $0.targetPolicy != .any },
      "Every target field needs an explicit input policy")
check(Set(tools.map(\.summaryKind)).count == SummaryKind.allCases.count,
      "Every summary strategy needs catalog coverage")
check(ToolCatalog.groups(from: tools).map(\.name) == [
    "Reports", "Local Network", "IP, Routing and Registration", "DNS", "Mail",
    "TLS, Web and Ports", "Utilities"
], "Section order changed")
let network = tools.first { $0.title == "Network Lookup" }!
check(network.optionDefault && network.optionArgument == "--quick", "Quick lookup metadata")
let zoneDiscovery = tools.first { $0.title == "DNS Zone Discovery" }!
check(zoneDiscovery.summaryKind == .report && zoneDiscovery.optionArgument == "--deep" && !zoneDiscovery.optionDefault,
      "DNS Zone Discovery must offer an optional Deep report")
let rpki = tools.first { $0.title == "RPKI Validation" }!
check(rpki.usesResolver && rpki.targetPolicy == .asn && rpki.secondaryInputPolicy == .ipPrefix,
      "RPKI validation requires both an origin ASN and an IP prefix")
check(rpki.command.contains("resource=$1") && rpki.command.contains("prefix=$2"),
      "RPKI validation sends both required RIPEstat parameters")
let propagationTool = tools.first { $0.title == "DNS Propagation" }!
check(propagationTool.optionArgument == "--all" && propagationTool.targetPolicy == .dnsTarget,
      "DNS propagation can compare every relevant record type")
let zoneTransfer = tools.first { $0.title == "DNS Zone Transfer" }!
check(zoneTransfer.command.contains("netmin-dns-zone-transfer.sh"),
      "Zone transfers query authoritative servers through the bundled helper")
let dnsA = tools.first { $0.title == "DNS A" }!
check(dnsA.supportsCustomResolver && !zoneDiscovery.supportsCustomResolver,
      "Direct DNS queries, but not composite discovery, offer a custom resolver")
let resolverCommand = CommandTemplate.command(for: dnsA, resolver: "1.1.1.1")
check(resolverCommand.hasPrefix("set -o pipefail; ") && resolverCommand.contains("/usr/bin/dig @\"$2\""),
      "Commands preserve pipeline failures and inject the custom resolver")
let resolverCopy = CommandTemplate.reusableCommand(
    for: dnsA, target: "example.org", resolver: "1.1.1.1", optionEnabled: false
)
check(resolverCopy.contains("@\"$2\"") && resolverCopy.hasSuffix("'example.org' '1.1.1.1'"),
      "Copied DNS commands preserve the selected resolver safely")
let dnssecValidation = tools.first { $0.title == "DNSSEC Validation" }!
let daneValidation = tools.first { $0.title == "DANE Validation" }!
check(dnssecValidation.supportsCustomResolver && daneValidation.supportsCustomResolver,
      "DNSSEC and DANE validation offer a custom validating resolver")
let validationCommand = CommandTemplate.command(for: dnssecValidation, resolver: "9.9.9.9")
check(validationCommand.hasSuffix("\"$2\""),
      "DNSSEC validation passes the selected resolver to its helper")
let validationCopy = CommandTemplate.reusableCommand(
    for: daneValidation, target: "_443._tcp.example.org", resolver: "9.9.9.9", optionEnabled: false
)
check(validationCopy.hasSuffix("'_443._tcp.example.org' '9.9.9.9'"),
      "Copied DANE validation commands preserve the selected resolver safely")
let sweep = tools.first { $0.title == "Local Device Sweep" }!
check(sweep.usesTarget && sweep.allowsEmptyTarget && !sweep.requiresTarget,
      "Local Device Sweep must run without a manually entered CIDR")
check(sweep.maximumDuration == 300, "Local Device Sweep needs the extended execution limit")
check(tools.first { $0.title == "Network Quality" }?.maximumDuration == 120,
      "Network Quality needs the extended execution limit")
check(tools.allSatisfy { $0.maximumDuration >= 45 }, "Every command needs a useful execution limit")
let target = "ross.gdn'; echo unsafe"
let reusable = CommandTemplate.reusableCommand(for: network, target: target, resolver: "", optionEnabled: true)
check(reusable.contains("'\\''"), "Copied commands shell-quote apostrophes")
check(reusable.contains("--quick"), "Copied command keeps the selected depth")
check(reusable.hasPrefix("NETMIN_HELPERS="), "Copied composite commands include their helper location")
let childEnvironment = CommandTemplate.environment(resourcesURL: nil)
check(childEnvironment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin", "Commands use only system tools")
check(childEnvironment["HOME"] == nil && childEnvironment["HTTP_PROXY"] == nil,
      "Commands do not inherit parent credentials, proxy settings, or home-directory state")
let whois = tools.first { $0.title == "WHOIS" }!
check(whois.requiresTarget, "WHOIS must still require a target")
let output = "% IANA WHOIS server\nrefer: whois.nic.gdn\ndomain: GDN\n"
let run = ToolRun(tool: whois, target: "ross.gdn", command: "whois ross.gdn", output: output,
                  exitCode: 0, startedAt: Date(), duration: 1.4)
check(ResultInterpreter.insight(for: run)?.severity == .warning, "IANA-only WHOIS is partial")
check(ResultInterpreter.fields(for: run).contains { $0.label == "Domain" && $0.value == "GDN" },
      "WHOIS fields are structured")
let completeWHOIS = ToolRun(
    tool: whois, target: "example.org", command: "whois example.org",
    output: "% IANA WHOIS server\nrefer: whois.example\nRegistrar: Example Registrar\nName Server: ns1.example\nRegistry Expiry Date: 2030-01-01\n",
    exitCode: 0, startedAt: Date(), duration: 0.4
)
check(ResultInterpreter.insight(for: completeWHOIS) == nil,
      "A complete WHOIS response must not show a partial-result warning")

let robots = tools.first { $0.title == "Robots.txt" }!
let redirectLoop = ToolRun(
    tool: robots, target: "www.example.org", command: robots.command,
    output: "curl: (47) Maximum (50) redirects followed\n", exitCode: 47,
    startedAt: Date(), duration: 0.8
)
let redirectInsight = ResultInterpreter.insight(for: redirectLoop)
check(redirectInsight?.title == "Robots.txt could not be retrieved" &&
      redirectInsight?.detail.contains("same URL repeatedly") == true,
      "Document redirect loops have a useful explanation")
let failedDocument = ResultInterpreter.summary(for: redirectLoop)
check(failedDocument.title == "No result returned" && failedDocument.sections.isEmpty &&
      failedDocument.metrics.contains { $0.label == "Exit status" && $0.value == "47" },
      "Failed document output is not interpreted as returned content")

func sampleRun(_ title: String, _ output: String) -> ToolRun {
    let tool = tools.first { $0.title == title }!
    return ToolRun(tool: tool, target: "example.org", command: tool.command, output: output,
                   exitCode: 0, startedAt: Date(), duration: 0.5)
}

let dns = ResultInterpreter.summary(for: sampleRun(
    "DNS A", "example.org. 300 IN A 192.0.2.1\nexample.org. 300 IN A 192.0.2.2\n"
))
check(dns.title == "DNS records" && dns.metrics.contains { $0.label == "Records" && $0.value == "2" },
      "DNS answers have a record summary")
let httpsRecord = ResultInterpreter.summary(for: sampleRun(
    "DNS HTTPS", "example.org. 300 IN TYPE65 \\# 27 000100000100060268320268330003000201bb00040004c0000201"
))
let httpsRows = httpsRecord.sections.compactMap(\.table).flatMap(\.rows)
check(httpsRows.contains { row in
    row.contains { $0.contains("alpn=h2,h3") } && row.contains { $0.contains("port=443") } &&
        row.contains { $0.contains("ipv4hint=192.0.2.1") }
}, "HTTPS service-binding wire data is decoded on the bundled macOS dig")
let unknownHTTPSKey = ResultInterpreter.summary(for: sampleRun(
    "DNS HTTPS", "example.org. 300 IN TYPE65 \\# 10 000100fde90003abcdef"
))
let unknownHTTPSRows = unknownHTTPSKey.sections.compactMap(\.table).flatMap(\.rows)
check(unknownHTTPSRows.flatMap { $0 }.contains { $0.contains("key65001=abcdef") },
      "Unknown HTTPS service parameters retain their numeric key and hexadecimal value")
let quality = ResultInterpreter.summary(for: sampleRun(
    "Network Quality", "Downlink Capacity: 328.227 Mbps\nUplink Capacity: 234.111 Mbps\nResponsiveness: Medium (110.056 milliseconds | 545 RPM)\n"
))
check(quality.metrics.contains { $0.label == "Responsiveness" && $0.value == "Medium" },
      "Network quality cards show the concise responsiveness rating")
check(quality.metrics.count == 3 && quality.metrics.allSatisfy(\.usesCompactValueStyle),
      "Network quality cards use one consistent value size")
let ping = ResultInterpreter.summary(for: sampleRun(
    "Ping", "4 packets transmitted, 4 packets received, 0.0% packet loss\nround-trip min/avg/max/stddev = 1.000/2.000/3.000/0.500 ms\n"
))
check(ping.metrics.contains { $0.label == "Average" && $0.value == "2.000 ms" },
      "Ping has latency metrics")
let http = ResultInterpreter.summary(for: sampleRun(
    "HTTP Headers", "HTTP/2 301\nlocation: https://www.example.org/\n\nHTTP/2 200\ncontent-type: text/html\n"
))
check(http.metrics.contains { $0.label == "Status" && $0.value == "301" } && http.sections.count == 2,
      "HTTP redirects are separated into responses")
let json = ResultInterpreter.summary(for: sampleRun(
    "RDAP Domain", #"{"objectClassName":"domain","ldhName":"EXAMPLE.ORG","status":["active"]}"#
))
check(json.sections.flatMap(\.rows).contains { $0.value == "EXAMPLE.ORG" },
      "JSON registry responses are flattened into useful fields")
let report = ResultInterpreter.summary(for: sampleRun(
    "Site Report", "Site report for example.org\n\nDNS\nexample.org. 300 IN A 192.0.2.1\n\nTLS handshakes\nProtocol version: TLSv1.3\n"
))
check(report.sections.count >= 2 && report.sections.contains { $0.title == "DNS" },
      "Composite reports preserve named sections")
let discoveryRun = sampleRun(
    "DNS Zone Discovery", "DNS zone discovery for example.org\nMode: Quick\nZone apex records\nexample.org. 300 IN A 192.0.2.1\nDiscovery status\nCompleteness: Partial discovery\nMethod: Quick public DNS probes\n"
)
let discovery = ResultInterpreter.summary(for: discoveryRun)
check(discovery.metrics.contains { $0.label == "Coverage" && $0.value == "Partial" } &&
      discovery.metrics.contains { $0.label == "Records" && $0.value == "1" },
      "DNS zone discovery reports honest coverage and record counts")
check(ResultInterpreter.insight(for: discoveryRun)?.severity == .warning,
      "Partial DNS discovery must not be labelled complete")
let tls = ResultInterpreter.summary(for: sampleRun(
    "TLS Handshake", "Protocol version: TLSv1.3\nCiphersuite: TLS_AES_256_GCM_SHA384\nVerification: OK\n"
))
check(tls.metrics.contains { $0.label == "Verification" && $0.value == "OK" },
      "TLS summaries expose negotiated security and verification")

func representativeOutput(for kind: SummaryKind) -> String {
    switch kind {
    case .report: return "DNS\nexample.org. 300 IN A 192.0.2.1\nTLS handshakes\nVerification: OK\n"
    case .publicAddress: return #"{"ip":"192.0.2.1","country":"Example"}"#
    case .discovery: return "Devices (1 found)\n192.0.2.1 device.local\n\nBonjour services\nPrinter Example Printer\n"
    case .networkTable: return "Destination Gateway Interface\ndefault 192.0.2.1 en0\n"
    case .configuration: return "Interface: en0\nAddress: 192.0.2.2\nStatus: Active\n"
    case .registration: return "Domain Name: EXAMPLE.ORG\nRegistrar: Example\nName Server: ns1.example.org\n"
    case .dnsRecords: return "example.org. 300 IN A 192.0.2.1\n"
    case .latency: return "4 packets transmitted, 4 received, 0.0% packet loss\nround-trip min/avg/max/stddev = 1.0/2.0/3.0/0.1 ms\n"
    case .tls: return "Protocol version: TLSv1.3\nCiphersuite: TLS_AES_256_GCM_SHA384\nVerification: OK\n"
    case .http: return "HTTP/2 200\ncontent-type: text/html\n"
    case .port: return "22/tcp open ssh\n443/tcp open https\n"
    case .document: return "Contact: mailto:security@example.org\nExpires: 2030-01-01\n"
    case .utility: return "Network: 192.0.2.0\nAddresses: 256\n"
    }
}

let sweepOutput = """
Fast local discovery
  192.168.50.0/24 via en0
  10.2.0.0/24 via utun4 (limited to the local /24 for speed)
Default gateway: 192.168.50.1

Method: macOS ping, TCP, neighbor cache and Bonjour
Devices (3 found)
IP address       Name                         Latency    Interface    MAC address        Vendor note
-------------------------------------------------------------------------------------------------------
192.168.50.1     -                            7.1 ms     en0          a4:2b:8c:11:22:33  -
192.168.50.2     This Mac                     -          en0          -                  -
192.168.50.19    christina                    110.5 ms   en0          02:aa:bb:cc:dd:ee  Private/randomized MAC

Common TCP services
192.168.50.1     HTTP (80), HTTPS (443)

Bonjour services
Printer          HP LaserJet
Secure printer   HP LaserJet
"""
let sweepSummary = ResultInterpreter.summary(for: sampleRun("Local Device Sweep", sweepOutput))
check(sweepSummary.devices.count == 3, "Sweep devices are parsed into a table")
check(sweepSummary.devices[0].isGateway && sweepSummary.devices[0].name == nil && sweepSummary.devices[0].latency == 7.1,
      "The gateway is marked and unnamed devices stay unnamed")
check(sweepSummary.devices[1].isThisMac && sweepSummary.devices[1].latency == nil, "This Mac is marked with no latency")
check(sweepSummary.devices[0].services == ["HTTP (80)", "HTTPS (443)"], "Open services attach to their device")
check(sweepSummary.devices[2].mac == "02:aa:bb:cc:dd:ee" && sweepSummary.devices[2].note == "Private/randomized MAC", "MAC and vendor notes survive")
check(sweepSummary.networks.count == 2 && sweepSummary.networks[1].limited, "Scanned networks and their limits are listed")
check(sweepSummary.metrics.first { $0.label == "Devices" }?.detail == "2 named · 1 unnamed", "Device metric counts names")
check(sweepSummary.metrics.first { $0.label == "Services" }?.value == "4", "Services count TCP and Bonjour entries")
check(sweepSummary.sections.contains { $0.title == "Bonjour services" && $0.table?.rows.count == 2 }, "Bonjour entries become a table")
check(sweepSummary.subtitle == "2 networks · en0, utun4" && sweepSummary.headline == "3 devices", "Sweep subtitle and headline")
check(ResultInterpreter.plainText(for: sweepSummary).contains("192.168.50.19\tchristina\t110.5 ms"), "Summaries render as plain text")
let emptySweep = sampleRun("Local Device Sweep", "Fast local discovery\n  192.168.50.0/24 via en0\n\nDevices (0 found)\n")
check(ResultInterpreter.insight(for: emptySweep)?.severity == .warning, "A sweep without devices warns")

let arp = ResultInterpreter.summary(for: sampleRun("ARP Table", "? (192.168.50.1) at a4:2b:8c:11:22:33 on en0 ifscope [ethernet]\nhost.local (192.168.50.7) at (incomplete) on en0 [ethernet]\n"))
check(arp.sections.first?.table?.rows.count == 2 && arp.metrics.contains { $0.label == "Resolved" && $0.value == "1" }, "ARP entries become a table")
let routes = ResultInterpreter.summary(for: sampleRun("Gateway and Routes", "   route to: default\n    gateway: 192.168.50.1\n  interface: en0\n\nRouting table\nRouting tables\n\nInternet:\nDestination        Gateway            Flags               Netif Expire\ndefault            192.168.50.1       UGScg                 en0\n127                127.0.0.1          UCS                   lo0\n"))
check(routes.metrics.contains { $0.label == "Gateway" && $0.value == "192.168.50.1" }, "The default gateway becomes a metric")
check(routes.sections.contains { $0.title == "Internet" && $0.table?.rows.count == 2 }, "Route tables keep their columns")
let trace = ResultInterpreter.summary(for: sampleRun("Traceroute", "traceroute to 1.1.1.1 (1.1.1.1), 15 hops max, ICMP echo probes\n 1  router (192.168.50.1)\n 2  * * *\n 3  one.one.one.one (1.1.1.1)  12.5 ms\n"))
check(trace.sections.first?.table?.rows.count == 3 && trace.metrics.contains { $0.label == "Timeouts" && $0.value == "1" }, "Traceroute hops become a table")
check(trace.metrics.contains { $0.label == "Destination" && $0.value == "Reached" && $0.detail == "12.5 ms" }, "The destination hop carries the round trip")
let unreached = ResultInterpreter.summary(for: sampleRun("Traceroute", "traceroute to 203.0.113.9 (203.0.113.9), 3 hops max, ICMP echo probes\n 1  router (192.168.50.1)\n 2  * * *\n 3  * * *\n\nThe destination did not answer within 3 hops.\n"))
check(unreached.title == "Destination not reached" && unreached.metrics.contains { $0.label == "Destination" && $0.tone == .warning }, "An unanswered trace is flagged")
let lookup = ResultInterpreter.summary(for: sampleRun("Network Lookup", "Network report for example.org\n\nBasic\nResolved address: 203.0.113.7\n\nRoute\ntraceroute to 203.0.113.7 (203.0.113.7), 15 hops max, ICMP echo probes\n 1  router (192.168.50.1)\n 2  10.0.0.1 (10.0.0.1)\n 3  example.org (203.0.113.7)  9.8 ms\n"))
check(lookup.sections.contains { $0.title == "Route" && $0.table?.rows.count == 3 }, "Report routes without per-hop timing still become hop tables")
let scan = ResultInterpreter.summary(for: sampleRun("Common Port Scan", "Common TCP ports on host\n\n22\topen\tSSH\n443\topen\tHTTPS\n\nOpen ports: 2\n"))
check(scan.title == "2 open ports" && scan.sections.first?.table?.statusColumn == 1, "Port scans show open ports with a status column")
let propagation = ResultInterpreter.summary(for: sampleRun("DNS Propagation", "Resolver 1.1.1.1\n192.0.2.1\n\nResolver 8.8.8.8\n192.0.2.1\n\nResolver 9.9.9.9\n\n"))
check(propagation.title == "Resolvers differ" && propagation.sections.first?.table?.rows.count == 3, "Propagation keeps resolvers without answers")
let site = ResultInterpreter.summary(for: sampleRun("Site Report", "Site report for example.org\n\nTCP reachability\nSSH      example.org:22    closed, filtered, or timed out\nHTTPS    example.org:443   open (0 s)\n\nTLS handshakes\nDefault\n  Protocol  : TLSv1.3\n  Verify return code: 0 (ok)\nTLS 1.2\n  Protocol  : TLSv1.2\n  Verify return code: 0 (ok)\n"))
check(site.sections.contains { $0.title == "TCP reachability" && $0.rows.contains { $0.label == "HTTPS · example.org:443" && $0.tone == .positive } },
      "Reachability rows are colour-coded and headings keep their acronyms")
check(site.sections.contains { $0.title == "TLS handshakes" && $0.rows.contains { $0.label == "TLS 1.2 · Protocol" } }, "Handshake blocks split by label")
check(site.metrics.contains { $0.label == "TLS" && $0.value == "TLSv1.3" }, "Reports surface headline metrics")

check(TargetInput.classify("example.com") == .domain, "Domains are detected")
check(TargetInput.classify("203.0.113.7") == .ipv4, "IPv4 addresses are detected")
check(TargetInput.classify("2001:db8::1") == .ipv6, "IPv6 addresses are detected")
check(TargetInput.classify("10.2.0.0/24") == .cidr(addresses: 256), "CIDR ranges count their addresses")
check(TargetInput.classify("10.2.0/24").isInvalid, "A short CIDR is rejected")
check(TargetInput.classify("300.1.1.1").isInvalid, "An out-of-range octet is rejected")
check(TargetInput.classify("mail.example.com:25") == .hostPort, "Host and port forms are detected")
check(TargetInput.classify("https://example.com/path") == .url, "URLs are detected")
check(TargetInput.classify("aa-bb-cc-dd-ee-ff") == .mac && TargetInput.classify("aa:bb:cc:dd:ee:ff") == .mac, "MAC addresses are detected")
check(TargetInput.classify("_443._tcp.example.com") == .service, "Service names are detected")
check(TargetInput.classify("selector._domainkey.example.com") == .domain, "DKIM selectors stay valid")
check(TargetInput.classify("münich.example") == .domain, "Unicode names stay valid for Punycode")
check(TargetInput.classify("bad target").isInvalid && TargetInput.classify("  ") == .empty, "Spaces are rejected and blanks are empty")
check(tools.first { $0.title == "IP Information" }!.validatedTargetKind("example.org").isInvalid,
      "IP-only tools reject hostnames")
check(!rpki.validatedTargetKind("AS13335").isInvalid && !rpki.validatedTargetKind("13335").isInvalid &&
      rpki.validatedTargetKind("example.org").isInvalid,
      "RPKI origin input accepts prefixed or bare ASNs and rejects domains")
check(!rpki.validatedSecondaryInputKind("1.1.1.0/24").isInvalid &&
      rpki.validatedSecondaryInputKind("1.1.1.1").isInvalid,
      "RPKI prefix input requires a CIDR prefix")
check(tools.first { $0.title == "HTTP Headers" }!.validatedTargetKind("ftp://example.org").isInvalid,
      "HTTP tools reject non-HTTP URL schemes")

let defaults = ToolRun(tool: whois, target: "x", command: "c", output: "", exitCode: 0, startedAt: Date(), duration: 0)
check(defaults.resolver.isEmpty && !defaults.optionEnabled, "ToolRun keeps its original memberwise initializer")

for tool in tools {
    let candidate = ToolRun(tool: tool, target: "example.org", command: tool.command,
                            output: representativeOutput(for: tool.summaryKind), exitCode: 0,
                            startedAt: Date(), duration: 0.1)
    let summary = ResultInterpreter.summary(for: candidate)
    check(!summary.title.isEmpty && !summary.detail.isEmpty && !summary.sections.isEmpty,
          "\(tool.title) must always produce a visible summary")
}
var runnerFinished = false
Task { @MainActor in
    let runner = CommandRunner()
    let fixture = ToolDefinition(
        id: "test/runner", group: "Test", title: "Runner",
        command: "/usr/bin/printf '<%s>\\n' \"$1\"", placeholder: "Target",
        resolverPlaceholder: nil, summary: "Test", optionLabel: nil,
        optionArgument: nil, optionDefault: false, progressMessage: "Testing…"
    )
    runner.start(tool: fixture, target: target, resolver: "", optionEnabled: false)
    let deadline = Date().addingTimeInterval(5)
    while runner.result == nil && Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    check(runner.result?.exitCode == 0, "Command runner finishes successfully")
    check(runner.result?.output == "<\(target)>\n", "Command runner preserves a literal target")
    check(runner.startedAt == nil, "A completed runner clears its live start time")

    let streaming = ToolDefinition(
        id: "test/streaming", group: "Test", title: "Streaming",
        command: "/usr/bin/printf 'first\\n'; /bin/sleep 0.4; /usr/bin/printf 'second\\n'",
        placeholder: "", resolverPlaceholder: nil, summary: "Test", optionLabel: nil,
        optionArgument: nil, optionDefault: false, progressMessage: "Streaming…"
    )
    runner.start(tool: streaming, target: "", resolver: "", optionEnabled: false)
    let firstDeadline = Date().addingTimeInterval(2)
    while !runner.output.contains("first") && Date() < firstDeadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    check(runner.output.contains("first") && runner.result == nil,
          "Live output must arrive before the command completes")
    let streamDeadline = Date().addingTimeInterval(3)
    while runner.result == nil && Date() < streamDeadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    check(runner.result?.output == "first\nsecond\n", "Streaming output remains complete")

    let sleepy = ToolDefinition(
        id: "test/timeout", group: "Test", title: "Timeout",
        command: "/bin/sleep 5", placeholder: "", resolverPlaceholder: nil,
        summary: "Test", optionLabel: nil, optionArgument: nil,
        optionDefault: false, progressMessage: "Waiting…"
    )
    runner.start(tool: sleepy, target: "", resolver: "", optionEnabled: false, timeout: 0.2)
    let timeoutDeadline = Date().addingTimeInterval(3)
    while runner.result == nil && Date() < timeoutDeadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    check(runner.result?.output.contains("Netmin stopped this command after") == true,
          "Commands that exceed their time limit are stopped with an explanation")
    check(runner.result?.exitCode != 0, "Timed-out commands do not report success")

    let noisy = ToolDefinition(
        id: "test/output-limit", group: "Test", title: "Output limit",
        command: "/usr/bin/yes x", placeholder: "", resolverPlaceholder: nil,
        summary: "Test", optionLabel: nil, optionArgument: nil,
        optionDefault: false, progressMessage: "Reading…"
    )
    runner.start(tool: noisy, target: "", resolver: "", optionEnabled: false, timeout: 3, outputLimit: 1_024)
    let outputDeadline = Date().addingTimeInterval(3)
    while runner.result == nil && Date() < outputDeadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    check(runner.result?.output.contains("Netmin stopped this command after it produced") == true
          && runner.result?.output.contains("bytes of output") == true,
          "Commands that exceed the output limit are stopped with an explanation")
    check((runner.result?.output.utf8.count ?? 0) < 1_200, "The stored output remains bounded")
    runnerFinished = true
}
let runnerDeadline = Date().addingTimeInterval(12)
while !runnerFinished && Date() < runnerDeadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
}
check(runnerFinished, "Command runner fixture timed out")
print("Netmin: 84 summaries, validation, streaming, timeouts, and bounded execution passed")
'''

with tempfile.TemporaryDirectory(prefix='netmin-tests-', dir='/private/tmp') as directory:
    folder = Path(directory)
    main = folder / 'main.swift'
    main.write_text(fixture)
    compiler = swift_compiler()
    command = compiler + [
        '-swift-version', '5', '-module-cache-path', str(folder / 'modules'),
        str(APP / 'Localization.swift'), str(APP / 'ToolDefinition.swift'), str(APP / 'ToolCatalog.swift'),
        str(APP / 'CommandTemplate.swift'), str(APP / 'CommandRunner.swift'),
        str(APP / 'ResultInterpreter.swift'), str(APP / 'TargetInput.swift'), str(main), '-o', str(folder / 'tests')
    ]
    environment = os.environ.copy()
    subprocess.run(command, check=True, env=environment)
    subprocess.run([str(folder / 'tests'), str(CATALOG)], check=True, timeout=40)
