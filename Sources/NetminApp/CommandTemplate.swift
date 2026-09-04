import Foundation

enum CommandTemplate {
    static func reusableCommand(for tool: ToolDefinition, target: String, resolver: String, optionEnabled: Bool) -> String {
        let option = optionEnabled ? (tool.optionArgument ?? "") : ""
        let values = [target, resolver, option]
        let command = command(for: tool, resolver: resolver)
        var highestArgument = 0
        for index in 1...3 where usesArgument(index, in: command) { highestArgument = index }
        var parts: [String] = []
        if command.contains("$NETMIN_HELPERS"), let resources = AppResources.resourcesURL {
            parts.append("NETMIN_HELPERS=\(shellQuote(resources.appendingPathComponent("Scripts").path))")
        }
        parts += ["/bin/bash", "-c", shellQuote(command), "--"]
        if highestArgument > 0 {
            parts.append(contentsOf: values.prefix(highestArgument).map(shellQuote))
        }
        return parts.joined(separator: " ")
    }

    static func arguments(for tool: ToolDefinition, target: String, resolver: String, optionEnabled: Bool) -> [String] {
        ["-c", command(for: tool, resolver: resolver), "--", target, resolver,
         optionEnabled ? (tool.optionArgument ?? "") : ""]
    }

    /// Adds the optional resolver argument in the form expected by each supported DNS command.
    static func command(for tool: ToolDefinition, resolver: String) -> String {
        var command = tool.command
        if tool.supportsCustomResolver, !resolver.isEmpty {
            if tool.title == "DNSSEC Validation" || tool.title == "DANE Validation" {
                command += " \"$2\""
            } else if let executable = command.range(of: "/usr/bin/dig") {
                command.replaceSubrange(executable, with: "/usr/bin/dig @\"$2\"")
            }
        }
        // Preserve the first failing status in pipelines such as curl-to-jq and dig-to-awk.
        return "set -o pipefail; " + command
    }

    static func environment(resourcesURL: URL?) -> [String: String] {
        // Do not pass credentials, proxy settings, or developer overrides from the parent app to
        // network utilities. Only locale and temporary-directory settings affect expected output.
        let parent = ProcessInfo.processInfo.environment
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "NO_COLOR": "1"]
        for key in ["TMPDIR", "LANG", "LC_ALL"] {
            if let value = parent[key] { environment[key] = value }
        }
        if let resourcesURL {
            environment["NETMIN_HELPERS"] = resourcesURL.appendingPathComponent("Scripts").path
        }
        return environment
    }

    private static func usesArgument(_ index: Int, in command: String) -> Bool {
        command.contains("$\(index)") || command.contains("${\(index)")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
