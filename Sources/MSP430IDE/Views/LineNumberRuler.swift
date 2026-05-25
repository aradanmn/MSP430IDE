import AppKit

final class LineNumberRuler: NSRulerView {
    weak var sourceTextView: NSTextView?

    init(textView: NSTextView) {
        self.sourceTextView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 40

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
        textView.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    @objc private func textDidChange(_ note: Notification) {
        needsDisplay = true
    }

    @objc private func boundsDidChange(_ note: Notification) {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = sourceTextView,
              let layoutManager = tv.layoutManager,
              let container = tv.textContainer else { return }

        let bgColor = NSColor.textBackgroundColor
        bgColor.setFill()
        rect.fill()

        let nsString = tv.string as NSString
        let visibleRect = tv.visibleRect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        var startLine = 1
        if visibleCharRange.location > 0 {
            let prior = NSRange(location: 0, length: visibleCharRange.location)
            nsString.enumerateSubstrings(in: prior, options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                startLine += 1
            }
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        var lineNumber = startLine
        let inset = tv.textContainerInset.height

        nsString.enumerateSubstrings(in: visibleCharRange, options: [.byLines, .substringNotRequired]) { _, substringRange, _, _ in
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: substringRange.location)
            var effectiveRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            let y = lineRect.minY - visibleRect.minY + inset
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attrs)
            let x = self.ruleThickness - size.width - 6
            label.draw(at: NSPoint(x: x, y: y + 1), withAttributes: attrs)
            lineNumber += 1
        }
    }
}
