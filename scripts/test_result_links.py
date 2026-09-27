#!/usr/bin/env python3
"""Exercise native result links, truncation, selection, and Escape with keyboard focus."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

fixture = r'''
import AppKit
import SwiftUI

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

@MainActor func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T { return match }
    for child in view.subviews {
        if let match = descendant(type, in: child) { return match }
    }
    return nil
}

@main
struct ResultLinkTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let view = LinkedResultTextView(frame: .zero)
        let url = URL(string: "https://icann.org/epp#clientTransferProhibited")!
        let value = "clientTransferProhibited \(url.absoluteString)\n日本語: \(url.absoluteString)"
        let text = NSMutableAttributedString(string: value)
        let firstLink = (value as NSString).range(of: url.absoluteString)
        let secondLink = (value as NSString).range(of: url.absoluteString, options: .backwards)
        text.addAttribute(.link, value: url, range: firstLink)
        text.addAttribute(.link, value: url, range: secondLink)
        view.setContent(text, color: .labelColor)

        // Only link ranges receive a hand cursor; the rest stays selectable text.
        check(!view.isEditable && view.isSelectable, "Results must remain selectable and read-only")
        check((view.linkTextAttributes?[.cursor] as? NSCursor) === NSCursor.pointingHand,
              "Links must use the pointing-hand cursor")
        check(view.textStorage?.attribute(.cursor, at: 0, effectiveRange: nil) == nil,
              "Plain text must keep its normal text-selection cursor")
        check(view.textStorage?.attribute(.link, at: firstLink.location, effectiveRange: nil) as? URL == url &&
              view.textStorage?.attribute(.link, at: secondLink.location, effectiveRange: nil) as? URL == url,
              "Every link must preserve its target and fragment")
        check(view.string == value, "Native rendering must preserve literal text and line breaks")

        // Long links truncate each source line without hiding other status entries.
        let wide = view.fittingSize(width: 850)
        view.setFrameSize(wide)
        let narrow = view.fittingSize(width: 220)
        check(abs((view.textContainer?.containerSize.width ?? 0) - wide.width) < 1,
              "Rejected layout proposals must not shrink the visible text container")
        view.setFrameSize(narrow)
        check(narrow.height == wide.height, "Long links must stay on their original lines")
        guard let layout = view.layoutManager, let container = view.textContainer else {
            fatalError("Result text layout is missing")
        }
        layout.ensureLayout(for: container)
        check(layout.usedRect(for: container).width <= 221, "Truncated links must fit the available width")
        var lines = 0
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, _, _, _, _ in
            lines += 1
        }
        check(lines == 2, "Both source lines must remain visible without extra wrapping")
        check(layout.truncatedGlyphRange(inLineFragmentForGlyphAt: 0).location != NSNotFound,
              "Long links must display a truncation ellipsis")
        check(view.string == value && view.textStorage?.attribute(.link, at: firstLink.location, effectiveRange: nil) as? URL == url,
              "Truncation must preserve the full text and link destination")
        check(view.fittingSize(width: 850) == wide, "Resizing back must restore the original text height")
        view.setFrameSize(wide)
        layout.ensureLayout(for: container)
        check(layout.truncatedGlyphRange(inLineFragmentForGlyphAt: 0).location == NSNotFound,
              "A wide row must display the complete link")

        // SwiftUI redraws must not clear an existing selection.
        let selection = NSRange(location: 0, length: 24)
        view.setSelectedRange(selection)
        view.setContent(text, color: .labelColor)
        check(view.selectedRange() == selection, "Unchanged result text must preserve selection")

        // Reproduce the focus left behind after activating a link without opening a browser.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 140),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        check(window.makeFirstResponder(view), "Linked text must accept selection focus")
        var cancellations = 0
        view.onCancel = { cancellations += 1 }
        guard let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                           characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                           isARepeat: false, keyCode: 53) else {
            fatalError("Cannot create Escape event")
        }
        window.sendEvent(escape)
        check(cancellations == 1, "Escape must trigger New Lookup with linked text as first responder")
        window.close()
        // Exercise SwiftUI's real proposal/placement sequence inside the result-row layout.
        let hosted = NSHostingView(rootView:
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("Domain Status").frame(width: 200, alignment: .leading)
                LinkedResultText(text: text, textColor: .labelColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        )
        let hostedWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 140),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        hostedWindow.isReleasedWhenClosed = false
        hostedWindow.contentView = hosted
        for width: CGFloat in [1000, 500, 1000] {
            hostedWindow.setContentSize(NSSize(width: width, height: 140))
            hosted.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            hosted.layoutSubtreeIfNeeded()
            guard let linked = descendant(LinkedResultTextView.self, in: hosted),
                  let linkedLayout = linked.layoutManager, let linkedContainer = linked.textContainer else {
                fatalError("SwiftUI did not create the linked result view")
            }
            check(abs(linked.bounds.width - (width - 254)) < 1,
                  "The linked result must use the entire value column")
            check(abs(linkedContainer.containerSize.width - linked.bounds.width) < 1,
                  "Visible text must use the placed width, not an earlier layout proposal")
            linkedLayout.ensureLayout(for: linkedContainer)
            let truncated = linkedLayout.truncatedGlyphRange(inLineFragmentForGlyphAt: 0).location != NSNotFound
            check(truncated == (width == 500), "Only a genuinely narrow row should truncate the URL")
        }
        hostedWindow.close()
        print("Result links: hand cursor, selection, truncation, SwiftUI width, resize, and focused Escape passed")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='netmin-result-links-', dir='/private/tmp') as folder_name:
    folder = Path(folder_name)
    main = folder / 'main.swift'
    main.write_text(fixture)
    output = folder / 'result-links-test'
    subprocess.run(swift_compiler() + [
        '-parse-as-library', '-swift-version', '5', '-warnings-as-errors',
        '-module-cache-path', str(folder / 'modules'), '-target', 'arm64-apple-macos14.0',
        str(ROOT / 'Sources/NetminApp/LinkedResultText.swift'), str(main), '-o', str(output),
    ], check=True)
    subprocess.run([str(output)], check=True, timeout=30)
