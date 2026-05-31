import SwiftUI
import AppKit

/// Read-only rendered Markdown, shown in place of the source editor when a
/// `.md` file is in Preview mode.
struct MarkdownView: NSViewRepresentable {
    @ObservedObject var buffer: TextBuffer

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.textStorage?.setAttributedString(MarkdownRenderer.render(buffer.text))

        // Save scroll position so switching tabs restores where you were.
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observe(scrollView: scrollView, buffer: buffer)

        // Restore prior scroll position once layout settles.
        let savedOrigin = buffer.savedScrollOrigin
        Task { @MainActor [weak scrollView] in
            guard let sv = scrollView else { return }
            sv.contentView.scroll(to: savedOrigin)
            sv.reflectScrolledClipView(sv.contentView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coord = context.coordinator

        // Switched to a different markdown file in the shared pane: save the
        // old scroll position, re-render, restore the new file's position.
        if coord.url != buffer.url {
            if let sv = coord.scrollViewRef { coord.buffer?.savedScrollOrigin = sv.contentView.bounds.origin }
            coord.rebind(buffer: buffer)
            textView.textStorage?.setAttributedString(MarkdownRenderer.render(buffer.text))
            coord.lastText = buffer.text
            let origin = buffer.savedScrollOrigin
            Task { @MainActor [weak scrollView] in
                guard let sv = scrollView else { return }
                sv.contentView.scroll(to: origin)
                sv.reflectScrolledClipView(sv.contentView)
            }
            return
        }
        if coord.lastText != buffer.text {
            textView.textStorage?.setAttributedString(MarkdownRenderer.render(buffer.text))
            coord.lastText = buffer.text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(buffer: buffer) }

    final class Coordinator {
        var lastText: String
        private(set) var url: URL
        private(set) var buffer: TextBuffer?
        private(set) weak var scrollViewRef: NSScrollView?

        init(buffer: TextBuffer) {
            self.lastText = buffer.text
            self.url = buffer.url
            self.buffer = buffer
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        func observe(scrollView: NSScrollView, buffer: TextBuffer) {
            self.scrollViewRef = scrollView
            self.buffer = buffer
            self.url = buffer.url
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func rebind(buffer: TextBuffer) {
            self.buffer = buffer
            self.url = buffer.url
        }

        @objc private func boundsDidChange(_ note: Notification) {
            guard let sv = scrollViewRef else { return }
            buffer?.savedScrollOrigin = sv.contentView.bounds.origin
        }
    }
}
