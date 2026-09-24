#!/usr/bin/env python3
"""Materialize Netmin's privacy panel and verify its document geometry."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

fixture = r'''
import AppKit

func localized(_ value: String) -> String { value }

enum AppLinks {
    static let privacyPolicy = URL(string: "https://min.tools/netmin/privacy/")!
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T { return match }
    for child in view.subviews {
        if let match = descendant(type, in: child) { return match }
    }
    return nil
}

@main
enum PrivacyPanelTest {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        PrivacyPolicyController.shared.show()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        guard let panel = NSApp.windows.first(where: { $0.title == "Privacy Policy" }),
              let content = panel.contentView,
              let scroll = descendant(NSScrollView.self, in: content),
              let textView = scroll.documentView as? NSTextView else {
            fatalError("Privacy panel hierarchy is incomplete")
        }

        let policyURL = URL(fileURLWithPath: CommandLine.arguments[1])
        textView.textStorage?.setAttributedString(
            PrivacyPolicyController.policyText(at: policyURL)
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        // Verify the complete policy fits the viewport and starts at its top-left edge.
        content.layoutSubtreeIfNeeded()
        check(!scroll.hasHorizontalScroller, "Privacy panel exposes horizontal scrolling")
        check(textView.textContainer?.widthTracksTextView == true, "Policy text does not track the viewport")
        check(abs(textView.frame.width - scroll.contentSize.width) < 1, "Policy document misses the viewport width")
        check(abs(scroll.contentView.bounds.origin.x) < 0.5, "Policy document opens horizontally offset")

        guard let layout = textView.layoutManager, let container = textView.textContainer else {
            fatalError("Privacy panel text layout is incomplete")
        }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let available = textView.frame.width - (2 * textView.textContainerInset.width)
        check(used.width <= available + 1, "Policy text extends beyond its visible width")
        let requiredHeight = used.height + (2 * textView.textContainerInset.height)
        check(textView.frame.height + 1 >= requiredHeight, "Policy document truncates vertical content")

        // Resize to the supported minimum and verify the same wrapping contract.
        panel.setContentSize(NSSize(width: 420, height: 320))
        content.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        check(abs(textView.frame.width - scroll.contentSize.width) < 1, "Resized policy document misses the viewport")
        check(abs(scroll.contentView.bounds.origin.x) < 0.5, "Resized policy document is horizontally offset")
        layout.ensureLayout(for: container)
        let resizedAvailable = textView.frame.width - (2 * textView.textContainerInset.width)
        let resizedUsed = layout.usedRect(for: container)
        check(resizedUsed.width <= resizedAvailable + 1, "Resized policy text does not wrap")
        let resizedHeight = resizedUsed.height + (2 * textView.textContainerInset.height)
        check(textView.frame.height + 1 >= resizedHeight, "Resized policy document truncates vertical content")

        panel.close()
        print("Netmin privacy panel: inset, wrapping and resize geometry passed")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='netmin-privacy-panel-', dir='/private/tmp') as folder_name:
    folder = Path(folder_name)
    main = folder / 'main.swift'
    main.write_text(fixture)
    output = folder / 'privacy-panel-test'
    command = swift_compiler() + [
        '-parse-as-library', '-swift-version', '5',
        '-module-cache-path', str(folder / 'modules'),
        '-target', 'arm64-apple-macos14.0',
        str(ROOT / 'Sources/NetminApp/PrivacyPolicy.swift'),
        str(main),
        '-framework', 'AppKit',
        '-o', str(output),
    ]
    subprocess.run(command, check=True)
    policy = ROOT / 'Sources/NetminApp/Resources/PRIVACY.md'
    subprocess.run([str(output), str(policy)], check=True, timeout=30)
