import AppKit
import Foundation

struct ToolRun: Equatable {
    let tool: ToolDefinition
    let target: String
    let command: String
    let output: String
    let exitCode: Int32
    let startedAt: Date
    let duration: TimeInterval
    var resolver = ""
    var optionEnabled = false

    var succeeded: Bool { exitCode == 0 }
}

@MainActor
final class CommandRunner: ObservableObject {
    private static let maximumOutputBytes = 8 * 1_024 * 1_024
    @Published private(set) var isRunning = false
    @Published private(set) var output = ""
    @Published private(set) var result: ToolRun?
    @Published private(set) var launchError: String?
    @Published private(set) var startedAt: Date?
    @Published private(set) var currentCommand = ""
    /// Called on the main actor with every completed run, after `result` is published.
    var onFinish: ((ToolRun) -> Void)?

    private var process: Process?
    private var outputPipe: Pipe?
    private var timeoutWorkItem: DispatchWorkItem?
    private var runGeneration = 0

    func start(
        tool: ToolDefinition,
        target: String,
        resolver: String,
        optionEnabled: Bool,
        timeout: TimeInterval? = nil,
        outputLimit requestedOutputLimit: Int? = nil
    ) {
        cancel()
        runGeneration += 1
        let generation = runGeneration
        let startedAt = Date()
        output = ""
        result = nil
        launchError = nil
        self.startedAt = startedAt
        currentCommand = CommandTemplate.reusableCommand(
            for: tool, target: target, resolver: resolver, optionEnabled: optionEnabled
        )
        isRunning = true

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = CommandTemplate.arguments(
            for: tool, target: target, resolver: resolver, optionEnabled: optionEnabled
        )
        process.environment = CommandTemplate.environment(resourcesURL: AppResources.resourcesURL)
        process.standardOutput = pipe
        process.standardError = pipe
        self.process = process
        outputPipe = pipe

        do {
            try process.run()
            let maximumDuration = timeout ?? tool.maximumDuration
            let outputLimit = requestedOutputLimit ?? CommandRunner.maximumOutputBytes
            let outputLimitText = outputLimit >= 1_024 * 1_024
                ? localizedFormat("%lld MB", Int64(outputLimit / (1_024 * 1_024)))
                : localizedFormat("%lld bytes", Int64(outputLimit))
            let timeoutWorkItem = DispatchWorkItem { [weak self, weak process] in
                guard let self, self.runGeneration == generation, let process, process.isRunning else { return }
                self.output.append("\n\n" + localizedFormat("Netmin stopped this command after %lld seconds.", Int64(maximumDuration)) + "\n")
                process.interrupt()
            }
            self.timeoutWorkItem = timeoutWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + maximumDuration, execute: timeoutWorkItem)
            DispatchQueue.global(qos: .userInitiated).async { [weak self, process, pipe] in
                let handle = pipe.fileHandleForReading
                var bytesRead = 0
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    let remaining = max(0, outputLimit - bytesRead)
                    let accepted = data.prefix(remaining)
                    bytesRead += accepted.count
                    let text = String(decoding: accepted, as: UTF8.self)
                    DispatchQueue.main.async { [weak self] in
                        guard self?.runGeneration == generation else { return }
                        self?.output.append(text)
                    }
                    if accepted.count < data.count || bytesRead >= outputLimit {
                        DispatchQueue.main.async { [weak self, process] in
                            guard let self, self.runGeneration == generation else { return }
                            self.output.append("\n\n" + localizedFormat("Netmin stopped this command after it produced %@ of output.", outputLimitText) + "\n")
                            if process.isRunning { process.interrupt() }
                        }
                        break
                    }
                }
                process.waitUntilExit()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.runGeneration == generation else { return }
                    self.timeoutWorkItem?.cancel()
                    self.timeoutWorkItem = nil
                    let run = ToolRun(
                        tool: tool,
                        target: target,
                        command: CommandTemplate.reusableCommand(
                            for: tool, target: target, resolver: resolver, optionEnabled: optionEnabled
                        ),
                        output: self.output,
                        exitCode: process.terminationStatus,
                        startedAt: startedAt,
                        duration: Date().timeIntervalSince(startedAt),
                        resolver: resolver,
                        optionEnabled: optionEnabled
                    )
                    self.result = run
                    self.isRunning = false
                    self.startedAt = nil
                    self.process = nil
                    self.outputPipe = nil
                    self.onFinish?(run)
                }
            }
        } catch {
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            launchError = error.localizedDescription
            isRunning = false
            self.startedAt = nil
            self.process = nil
            outputPipe = nil
        }
    }

    func cancel() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        guard let process, process.isRunning else { return }
        runGeneration += 1
        process.interrupt()
        isRunning = false
        startedAt = nil
        self.process = nil
        outputPipe = nil
    }

    func clear() {
        cancel()
        output = ""
        result = nil
        launchError = nil
        startedAt = nil
        currentCommand = ""
    }
}

enum AppResources {
    static var resourcesURL: URL? {
        #if NETMIN_SWIFTPM
        Bundle.module.url(forResource: "Resources", withExtension: nil) ?? Bundle.module.resourceURL
        #else
        Bundle.main.resourceURL
        #endif
    }
}
