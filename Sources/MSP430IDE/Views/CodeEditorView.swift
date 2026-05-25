import SwiftUI
import AppKit

struct CodeEditorView: NSViewRepresentable {
    @ObservedObject var buffer: TextBuffer

    func makeCoordinator() -> Coordinator {
        Coordinator(buffer: buffer)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = false

        let tv = scroll.documentView as! NSTextView
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindPanel = true
        tv.textColor = NSColor.textColor
        tv.insertionPointColor = NSColor.textColor
        tv.backgroundColor = NSColor.textBackgroundColor
        tv.drawsBackground = true
        tv.delegate = context.coordinator
        tv.isHorizontallyResizable = false
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.textContainer?.widthTracksTextView = true

        let ruler = LineNumberRuler(textView: tv)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true

        context.coordinator.textView = tv
        context.coordinator.ruler = ruler

        tv.string = buffer.text
        context.coordinator.applyHighlighting()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.buffer = buffer
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != buffer.text {
            let selected = tv.selectedRange()
            tv.string = buffer.text
            context.coordinator.applyHighlighting()
            let len = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(selected.location, len), length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var buffer: TextBuffer
        weak var textView: NSTextView?
        weak var ruler: LineNumberRuler?

        init(buffer: TextBuffer) {
            self.buffer = buffer
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            buffer.text = tv.string
            buffer.markDirty()
            applyHighlighting()
            ruler?.needsDisplay = true
        }

        func applyHighlighting() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            CHighlighter.highlight(storage: storage)
        }
    }
}
