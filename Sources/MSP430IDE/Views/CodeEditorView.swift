import SwiftUI
import AppKit

struct CodeEditorView: NSViewRepresentable {
    @ObservedObject var buffer: TextBuffer
    let gutter: GutterState

    func makeCoordinator() -> Coordinator {
        Coordinator(buffer: buffer, gutter: gutter)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.font = font
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.delegate = context.coordinator

        textView.string = buffer.text
        if let storage = textView.textStorage {
            HighlighterRegistry.highlighter(for: buffer.url).highlight(storage: storage)
        }

        context.coordinator.attach(textView: textView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.buffer = buffer
        context.coordinator.gutter = gutter
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != buffer.text {
            let prev = tv.selectedRange()
            tv.string = buffer.text
            if let storage = tv.textStorage {
                HighlighterRegistry.highlighter(for: buffer.url).highlight(storage: storage)
            }
            let len = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(prev.location, len), length: 0))
            context.coordinator.scheduleRecompute()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var buffer: TextBuffer
        var gutter: GutterState
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        init(buffer: TextBuffer, gutter: GutterState) {
            self.buffer = buffer
            self.gutter = gutter
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(textView: NSTextView, scrollView: NSScrollView) {
            self.textView = textView
            self.scrollView = scrollView

            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            textView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(frameDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: textView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(jumpToLine(_:)),
                name: .msp430EditorJumpToLine,
                object: nil
            )

            scheduleRecompute()
        }

        @objc private func jumpToLine(_ note: Notification) {
            guard let info = note.userInfo,
                  let url = info["url"] as? URL,
                  let line = info["line"] as? Int,
                  url == buffer.url,
                  let tv = textView else { return }
            let column = (info["column"] as? Int) ?? 1
            let nsString = tv.string as NSString
            var found: NSRange? = nil
            var current = 1
            nsString.enumerateSubstrings(
                in: NSRange(location: 0, length: nsString.length),
                options: .byLines
            ) { _, substringRange, _, stop in
                if current == line {
                    found = substringRange
                    stop.pointee = true
                }
                current += 1
            }
            let lineRange = found ?? NSRange(location: 0, length: 0)
            let colOffset = max(0, column - 1)
            let target = min(lineRange.location + colOffset, lineRange.location + lineRange.length)
            let range = NSRange(location: min(target, nsString.length), length: 0)
            tv.scrollRangeToVisible(range)
            tv.setSelectedRange(range)
            tv.window?.makeFirstResponder(tv)
        }

        @objc private func boundsDidChange(_ note: Notification) {
            scheduleRecompute()
        }

        @objc private func frameDidChange(_ note: Notification) {
            scheduleRecompute()
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            buffer.text = tv.string
            buffer.markDirty()
            if let storage = tv.textStorage {
                HighlighterRegistry.highlighter(for: buffer.url).highlight(storage: storage)
            }
            scheduleRecompute()
        }

        func scheduleRecompute() {
            Task { @MainActor [weak self] in
                self?.recompute()
            }
        }

        private func recompute() {
            guard let tv = textView,
                  let layoutManager = tv.layoutManager,
                  let container = tv.textContainer else { return }

            let visibleRect = tv.visibleRect
            let nsString = tv.string as NSString
            let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
            layoutManager.ensureLayout(forGlyphRange: visibleGlyphRange)
            let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

            var startLine = 1
            if visibleCharRange.location > 0 {
                let prior = NSRange(location: 0, length: visibleCharRange.location)
                nsString.enumerateSubstrings(in: prior, options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                    startLine += 1
                }
            }

            let inset = tv.textContainerInset.height
            var lines: [GutterState.VisibleLine] = []
            var lineNumber = startLine

            nsString.enumerateSubstrings(in: visibleCharRange, options: [.byLines, .substringNotRequired]) { _, substringRange, _, _ in
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: substringRange.location)
                var effectiveRange = NSRange(location: 0, length: 0)
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
                let y = lineRect.minY - visibleRect.minY + inset
                lines.append(.init(number: lineNumber, y: y))
                lineNumber += 1
            }

            var totalLines = 1
            let fullRange = NSRange(location: 0, length: nsString.length)
            nsString.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                totalLines += 1
            }
            if totalLines > 1 { totalLines -= 1 }

            if gutter.visibleLines != lines {
                gutter.visibleLines = lines
            }
            if gutter.totalLines != totalLines {
                gutter.totalLines = totalLines
            }
        }
    }
}
