import Foundation

enum ToolCatalogError: LocalizedError {
    case resourceMissing
    case emptyCatalog

    var errorDescription: String? {
        switch self {
        case .resourceMissing: localized("The bundled Netmin tool catalog is missing.")
        case .emptyCatalog: localized("The Netmin tool catalog contains no valid tools.")
        }
    }
}

enum ToolCatalog {
    static func loadBundled() throws -> [ToolDefinition] {
        #if NETMIN_SWIFTPM
        let url = Bundle.module.url(forResource: "tools", withExtension: "tsv", subdirectory: "Resources")
            ?? Bundle.module.url(forResource: "tools", withExtension: "tsv")
        #else
        let url = Bundle.main.url(forResource: "tools", withExtension: "tsv")
        #endif
        guard let url else { throw ToolCatalogError.resourceMissing }
        return try load(from: url)
    }

    static func load(from url: URL) throws -> [ToolDefinition] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var group = "Other"
        var tools: [ToolDefinition] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                group = String(line.dropFirst().dropLast())
                continue
            }
            let fields = rawLine.components(separatedBy: "\t")
            guard fields.count >= 2 else { continue }
            let title = fields[0].trimmingCharacters(in: .whitespaces)
            let command = fields[1].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, !command.isEmpty else { continue }
            let usesResolver = command.contains("$2") || command.contains("${2")
            let descriptionIndex = usesResolver ? 4 : 3
            let optionIndex = descriptionIndex + 1
            let progressIndex = optionIndex + 3
            let targetPolicyIndex = progressIndex + 1
            let value: (Int) -> String = { index in fields.indices.contains(index) ? fields[index] : "" }
            let progress = value(progressIndex).nilIfEmpty ?? localizedFormat("Running %@…", localized(title))
            let rawPolicy = value(targetPolicyIndex).lowercased()
            let allowsEmptyTarget = rawPolicy == "optional" || rawPolicy.hasPrefix("optional-")
            let policyName = rawPolicy.hasPrefix("optional-") ? String(rawPolicy.dropFirst("optional-".count)) : rawPolicy
            let targetPolicy = TargetPolicy(rawValue: policyName) ?? .any
            let secondaryInputPolicy = TargetPolicy(rawValue: value(targetPolicyIndex + 1).lowercased()) ?? .hostOrIP
            tools.append(ToolDefinition(
                id: "\(group)/\(title)",
                group: group,
                title: title,
                command: command,
                placeholder: value(2).nilIfEmpty ?? "IP address or hostname",
                resolverPlaceholder: usesResolver ? (value(3).nilIfEmpty ?? "DNS server") : nil,
                summary: value(descriptionIndex).nilIfEmpty ?? localizedFormat("Run the %@ tool", localized(title)),
                optionLabel: value(optionIndex).nilIfEmpty,
                optionArgument: value(optionIndex + 1).nilIfEmpty,
                optionDefault: value(optionIndex + 2).lowercased() == "on",
                progressMessage: progress,
                allowsEmptyTarget: allowsEmptyTarget,
                targetPolicy: targetPolicy,
                secondaryInputPolicy: secondaryInputPolicy
            ))
        }
        guard !tools.isEmpty else { throw ToolCatalogError.emptyCatalog }
        return tools
    }

    static func groups(from tools: [ToolDefinition]) -> [ToolGroup] {
        var names: [String] = []
        var grouped: [String: [ToolDefinition]] = [:]
        for tool in tools {
            if grouped[tool.group] == nil { names.append(tool.group) }
            grouped[tool.group, default: []].append(tool)
        }
        return names.map { ToolGroup(name: $0, tools: grouped[$0] ?? []) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
