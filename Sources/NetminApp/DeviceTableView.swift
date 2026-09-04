import SwiftUI

/// The device table of a Local Device Sweep: filterable, with latency bars, interface chips,
/// and per-row actions that launch other tools against the device.
struct DeviceTableView: View {
    let devices: [DiscoveredDevice]
    @ObservedObject var model: AppModel
    @State private var filter = ""
    @State private var showMAC = false

    private var filtered: [DiscoveredDevice] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return devices }
        return devices.filter { device in
            device.address.localizedCaseInsensitiveContains(needle)
                || (device.name ?? "").localizedCaseInsensitiveContains(needle)
                || device.interface.localizedCaseInsensitiveContains(needle)
                || (device.mac ?? "").localizedCaseInsensitiveContains(needle)
                || device.services.joined(separator: " ").localizedCaseInsensitiveContains(needle)
        }
    }

    private var maxLatency: Double { devices.compactMap(\.latency).max() ?? 1 }
    private var hasMAC: Bool { devices.contains { $0.mac != nil } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Devices")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Chip(text: String(filtered.count), compact: true)
                Spacer()
                SearchField(placeholder: "Filter by IP, name, interface", text: $filter, compact: true)
                    .frame(width: 280)
                Text(localized(hasMAC ? (showMAC ? "MAC and vendor shown" : "MAC and vendor hidden") : "MAC and vendor hidden — empty in this run"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                if hasMAC {
                    Button(localized(showMAC ? "Hide" : "Show")) { showMAC.toggle() }
                        .buttonStyle(.netmin(.link, size: .small))
                        .keyboardFocusable()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            Rectangle().fill(Theme.border).frame(height: 1)

            HStack(spacing: 14) {
                SectionLabel("IP address").frame(width: 160, alignment: .leading)
                SectionLabel("Name").frame(maxWidth: .infinity, alignment: .leading)
                SectionLabel("Latency").frame(width: 210, alignment: .leading)
                SectionLabel("Interface").frame(width: 110, alignment: .leading)
                if showMAC {
                    SectionLabel("MAC address").frame(width: 160, alignment: .leading)
                    SectionLabel("Vendor").frame(width: 150, alignment: .leading)
                }
                SectionLabel("Actions").frame(width: 110, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            Rectangle().fill(Theme.border).frame(height: 1)

            if filtered.isEmpty {
                Text(localizedFormat("No devices match “%@”", filter))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            }
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, device in
                if index > 0 { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 18) }
                DeviceRow(device: device, maxLatency: maxLatency, showMAC: showMAC, model: model)
            }
        }
        .card()
        .animation(.easeOut(duration: 0.15), value: showMAC)
    }
}

private struct DeviceRow: View {
    let device: DiscoveredDevice
    let maxLatency: Double
    let showMAC: Bool
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Text(device.address)
                .font(Theme.mono(13.5))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(width: 160, alignment: .leading)
            HStack(spacing: 8) {
                Text(device.name ?? localized("Unnamed"))
                    .font(.system(size: 13.5))
                    .foregroundStyle(device.name == nil ? Theme.textTertiary : Theme.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                if device.isThisMac { Chip(text: "you", mono: false, compact: true) }
                if device.isGateway { Chip(text: "gateway", mono: false, compact: true) }
                if !device.services.isEmpty {
                    Chip(
                        text: device.services.count == 1
                            ? localized("1 service")
                            : localizedFormat("%lld services", Int64(device.services.count)),
                        mono: false,
                        tone: .accent,
                        compact: true
                    )
                        .help(device.services.joined(separator: ", "))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            latency
                .frame(width: 210, alignment: .leading)
            Chip(text: device.interface, compact: true)
                .frame(width: 110, alignment: .leading)
            if showMAC {
                Text(device.mac ?? "—")
                    .font(Theme.mono(12.5))
                    .foregroundStyle(device.mac == nil ? Theme.textTertiary : Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(width: 160, alignment: .leading)
                Text(device.note ?? "—")
                    .font(.system(size: 12.5))
                    .foregroundStyle(device.note == nil ? Theme.textTertiary : Theme.textSecondary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
            HStack(spacing: 2) {
                Button("Ping") { model.run(toolTitled: "Ping", target: device.address) }
                    .buttonStyle(.netmin(.link, size: .small))
                    .keyboardFocusable()
                Button("Ports") { model.run(toolTitled: "Common Port Scan", target: device.address) }
                    .buttonStyle(.netmin(.link, size: .small))
                    .keyboardFocusable()
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .hoverHighlight(cornerRadius: 0)
        .contextMenu {
            Button("Copy Address") { model.copy(device.address) }
            if let name = device.name { Button("Copy Name") { model.copy(name) } }
            if let mac = device.mac { Button("Copy MAC Address") { model.copy(mac) } }
            Divider()
            Button("Ping") { model.run(toolTitled: "Ping", target: device.address) }
            Button("Common Port Scan") { model.run(toolTitled: "Common Port Scan", target: device.address) }
            Button("Reverse DNS") { model.run(toolTitled: "Reverse DNS", target: device.address) }
            Button("Windows Name Discovery") { model.run(toolTitled: "Windows Name Discovery", target: device.address) }
        }
    }

    @ViewBuilder private var latency: some View {
        if let value = device.latency {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Theme.latencyGradient)
                    .frame(width: max(8, 120 * value / max(maxLatency, 1)), height: 5)
                    .shadow(color: Theme.cyan.opacity(0.4), radius: 3)
                Text(ResultInterpreter.formatMilliseconds(value))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
        } else {
            Text(localized("no reply"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
