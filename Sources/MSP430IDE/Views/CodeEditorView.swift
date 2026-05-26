import SwiftUI
import AppKit

struct CodeEditorView: NSViewRepresentable {
    @ObservedObject var buffer: TextBuffer

    func makeCoordinator() -> Coordinator {
        Coordinator(buffer: buffer)
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
            CHighlighter.highlight(storage: storage)
        }

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.buffer = buffer
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != buffer.text {
            let prev = tv.selectedRange()
            tv.string = buffer.text
            if let storage = tv.textStorage {
                CHighlighter.highlight(storage: storage)
            }
            let len = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(prev.location, len), length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var buffer: TextBuffer
        weak var textView: NSTextView?

        init(buffer: TextBuffer) {
            self.buffer = buffer
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            buffer.text = tv.string
            buffer.markDirty()
            if let storage = tv.textStorage {
                CHighlighter.highlight(storage: storage)
            }
        }
    }
}
