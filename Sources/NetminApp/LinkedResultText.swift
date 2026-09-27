import AppKit
import SwiftUI

/// Selectable result text with native link hit testing and cursor handling.
struct LinkedResultText: NSViewRepresentable {
    let text: NSAttributedString
    let textColor: NSColor
    var onCancel: (() -> Void)? = nil

    func makeNSView(context: Context) -> LinkedResultTextView {
        LinkedResultTextView(frame: .zero)
    }

    func updateNSView(_ view: LinkedResultTextView, context: Context) {
        view.setContent(text, color: textColor)
        view.onCancel = onCancel
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LinkedResultTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        return nsView.fittingSize(width: width)
    }
}

final class LinkedResultTextView: NSTextView {
    static let resultFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    var onCancel: (() -> Void)?
    private var displayedContent: NSAttributedString?

    // This initializer creates TextKit before calling init(frame:textContainer:).
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        isHorizontallyResizable = false
        isVerticallyResizable = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        linkTextAttributes = [
            .foregroundColor: NSColor.controlAccentColor,
            .cursor: NSCursor.pointingHand
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Keep Escape mapped to New Lookup after a link or selection takes keyboard focus.
    override func cancelOperation(_ sender: Any?) {
        if let onCancel {
            onCancel()
        } else {
            super.cancelOperation(sender)
        }
    }

    /// Apply literal result text and preserve selection when the content has not changed.
    func setContent(_ text: NSAttributedString, color: NSColor) {
        let styled = NSMutableAttributedString(attributedString: text)
        // Keep each source line separate, truncating its tail instead of wrapping the URL.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        styled.addAttributes([.font: Self.resultFont, .foregroundColor: color, .paragraphStyle: paragraph],
                             range: NSRange(location: 0, length: styled.length))
        // TextKit adds layout attributes to its storage; compare our original input instead.
        if displayedContent?.isEqual(to: styled) != true {
            displayedContent = styled.copy() as? NSAttributedString
            textStorage?.setAttributedString(styled)
            invalidateIntrinsicContentSize()
        }
    }

    /// Measure proposals separately so rejected SwiftUI widths cannot change visible text.
    func fittingSize(width: CGFloat) -> NSSize {
        let storage = NSTextStorage(attributedString: displayedContent ?? NSAttributedString(string: ""))
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let height = max(layout.usedRect(for: container).height,
                         layout.defaultLineHeight(for: Self.resultFont))
        return NSSize(width: width, height: ceil(height))
    }
}
