import AppKit
import SwiftUI

private enum NetminCommand: Int {
    case overview = 2_001
    case rawOutput
    case findTool
    case run
    case runAgain
    case stop
    case copyResult
    case copySummary
    case copyCommand
}


@MainActor
private final class MinToolsAboutPanelController: NSWindowController {
    static let shared = MinToolsAboutPanelController()

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")
    private let copyrightLabel = NSTextField(labelWithString: "")
    private let profileButton = NSButton()

    private init() {
        let size = NSSize(width: 280, height: 174)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        versionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        copyrightLabel.font = .systemFont(ofSize: 11, weight: .medium)
        for label in [nameLabel, versionLabel, copyrightLabel] {
            label.alignment = .center
            label.textColor = .labelColor
        }

        profileButton.isBordered = false
        profileButton.attributedTitle = NSAttributedString(
            string: "GitHub.com/iliaross",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        profileButton.target = self
        profileButton.action = #selector(openProfile(_:))

        let stack = NSStackView(views: [
            iconView,
            nameLabel,
            versionLabel,
            copyrightLabel,
            profileButton
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setCustomSpacing(8, after: iconView)
        stack.setCustomSpacing(7, after: nameLabel)
        stack.setCustomSpacing(8, after: versionLabel)
        stack.setCustomSpacing(0, after: copyrightLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.addSubview(stack)
        panel.contentView = content
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 54),
            iconView.heightAnchor.constraint(equalToConstant: 54),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // show(applicationName): Refresh bundle details and present the About panel.
    func show(applicationName: String) {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let copyright = bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 Ilia Ross"

        iconView.image = NSApp.applicationIconImage
        nameLabel.stringValue = applicationName
        versionLabel.stringValue = "Version \(version) (\(build))"
        copyrightLabel.stringValue = copyright

        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // openProfile(sender): Open the author's public GitHub profile.
    @objc private func openProfile(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/iliaross") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class NetminAppDelegate: NSObject, NSApplicationDelegate {
    private static let didShowTrialWelcomeKey = "NetminDidShowTrialWelcome"
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIcon.make()
        installNativeCommands()
        Task { @MainActor in
            NetminProStore.shared.start()
            presentTrialWelcomeIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // presentTrialWelcomeIfNeeded(): Explain the app trial once on first launch.
    private func presentTrialWelcomeIfNeeded() {
        let store = NetminProStore.shared
        // Private maintainer builds are already unlocked and do not need public purchase guidance.
        guard !store.isLocalBuild,
              !NetminEdition.isExpiredTrialPreview else {
            return
        }
        // A completed disclosure may need to resolve the trial after migration.
        if UserDefaults.standard.bool(forKey: Self.didShowTrialWelcomeKey) {
            store.beginAppTrial()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = localized("30 days of full access")
        let trialDetails = [
            localized("Netmin includes a free 30-day full-access period. No subscription starts, and you will not be charged."),
            localized("After the trial, all 84 tools and raw output remain available with 5 diagnostic requests per day."),
            localized("Choose a yearly plan or lifetime access at any time to keep unlimited requests and Pro reports.")
        ]
        alert.informativeText = trialDetails.joined(separator: "\n\n")
        alert.addButton(withTitle: localized("Continue"))
        NSApp.activate(ignoringOtherApps: true)
        _ = alert.runModal()
        store.beginAppTrial()
        UserDefaults.standard.set(true, forKey: Self.didShowTrialWelcomeKey)
    }

    // showAbout(): Show the About panel with bundle metadata and author link.
    func showAbout() {
        MinToolsAboutPanelController.shared.show(applicationName: "Netmin")
    }

    @objc func showPrivacyPolicy(_ sender: Any?) {
        PrivacyPolicyController.shared.show()
    }

    // clearRecentData(): Confirm and remove saved targets and recent-run summaries.
    func clearRecentData() {
        let alert = NSAlert()
        alert.messageText = localized("Clear recent Netmin data?")
        alert.informativeText = localized("This removes saved targets and recent-run summaries from this Mac. It does not delete exported reports.")
        alert.addButton(withTitle: localized("Clear Recent Data"))
        alert.addButton(withTitle: localized("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { model.clearRecentData() }
    }

    // Install the custom View and Tools menus through AppKit to avoid a blank pop-up on cold
    // launch. The scene owns the application menu because SwiftUI rebuilds that menu.
    private func installNativeCommands() {
        guard let mainMenu = NSApp.mainMenu else { return }

        let windowIndex = mainMenu.items.firstIndex { $0.submenu === NSApp.windowsMenu }
            ?? mainMenu.items.firstIndex(where: { $0.title == "Window" || $0.title == localized("Window") })
            ?? mainMenu.items.count
        let viewMenu = mainMenu.items.first(where: { $0.title == "View" || $0.title == localized("View") })?.submenu
            ?? (windowIndex > 0 ? mainMenu.items[windowIndex - 1].submenu : nil)
        if let viewMenu {
            viewMenu.addItem(.separator())
            viewMenu.addItem(item(localized("Overview"), .overview, key: "1", modifiers: .command))
            viewMenu.addItem(item(localized("Raw Output"), .rawOutput, key: "2", modifiers: .command))
        }

        let tools = NSMenu(title: localized("Tools"))
        tools.autoenablesItems = true
        tools.addItem(item(localized("Find Tool…"), .findTool, key: "k", modifiers: .command))
        tools.addItem(.separator())
        tools.addItem(item(localized("Run"), .run, key: "\r", modifiers: .command))
        tools.addItem(item(localized("Run Again"), .runAgain, key: "r", modifiers: .command))
        tools.addItem(item(localized("Stop"), .stop, key: "\u{1b}"))
        tools.addItem(.separator())
        tools.addItem(item(localized("Copy Result"), .copyResult, key: "c", modifiers: [.command, .shift]))
        tools.addItem(item(localized("Copy Summary"), .copySummary))
        tools.addItem(item(localized("Copy Command"), .copyCommand, key: "c", modifiers: [.command, .option]))

        let toolsItem = NSMenuItem(title: localized("Tools"), action: nil, keyEquivalent: "")
        toolsItem.submenu = tools
        mainMenu.insertItem(toolsItem, at: windowIndex)
    }

    private func item(
        _ title: String,
        _ command: NetminCommand,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: #selector(performCommand(_:)), keyEquivalent: key)
        menuItem.target = self
        menuItem.tag = command.rawValue
        menuItem.keyEquivalentModifierMask = modifiers
        return menuItem
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let command = NetminCommand(rawValue: sender.tag) else { return }
        switch command {
        case .overview: model.showsRawOutput = false
        case .rawOutput: model.showsRawOutput = true
        case .findTool:
            guard let keyWindow = NSApp.keyWindow else { return }
            NotificationCenter.default.post(name: .focusSidebarSearch, object: keyWindow)
        case .run: model.runSelected()
        case .runAgain:
            if let run = model.runner.result { model.rerun(run) }
        case .stop: model.runner.cancel()
        case .copyResult:
            if let run = model.runner.result { model.copy(run.output) }
        case .copySummary:
            if !NetminProStore.shared.hasFullAccess {
                NetminProStore.shared.present(feature: .structuredReports)
            } else if let run = model.runner.result {
                model.copy(ResultInterpreter.plainText(for: model.summary(for: run)))
            }
        case .copyCommand:
            if let run = model.runner.result { model.copy(run.command) }
        }
    }
}

extension NetminAppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = NetminCommand(rawValue: menuItem.tag) else { return true }
        switch command {
        case .overview:
            menuItem.state = model.showsRawOutput ? .off : .on
            return true
        case .rawOutput:
            menuItem.state = model.showsRawOutput ? .on : .off
            return true
        case .run:
            return model.canRun
        case .runAgain:
            return model.runner.result != nil && !model.runner.isRunning
        case .stop:
            menuItem.isHidden = !model.runner.isRunning
            return model.runner.isRunning
        case .copyResult, .copyCommand:
            return model.runner.result != nil
        case .copySummary:
            return model.runner.result != nil
        case .findTool:
            return true
        }
    }
}

@main
struct NetminApplication: App {
    @NSApplicationDelegateAdaptor(NetminAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Netmin") {
            NetminRootView(model: appDelegate.model)
                .frame(minWidth: 980, minHeight: 660)
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(localized("About Netmin")) {
                    appDelegate.showAbout()
                }
                Divider()
                Button(localized("Netmin Pro…")) {
                    NetminProStore.shared.present()
                }
                Button(localized("Privacy Policy…")) {
                    appDelegate.showPrivacyPolicy(nil)
                }
                Button(localized("Clear Recent Data…")) {
                    appDelegate.clearRecentData()
                }
            }
        }
    }
}
