import SwiftUI
import AppKit

struct CodeEditorView: NSViewRepresentable {
    @ObservedObject var buffer: TextBuffer
    let gutter: GutterState
    var lsp: LSPClient?

    func makeCoordinator() -> Coordinator {
        Coordinator(buffer: buffer, gutter: gutter, lsp: lsp)
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

        // Restore saved cursor + scroll position. Deferred so layout finishes
        // before we attempt to scroll to a specific origin.
        let savedSel = buffer.savedSelection
        let savedOrigin = buffer.savedScrollOrigin
        Task { @MainActor [weak textView, weak scrollView] in
            guard let tv = textView, let sv = scrollView else { return }
            let len = (tv.string as NSString).length
            let loc = min(savedSel.location, len)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
            sv.contentView.scroll(to: savedOrigin)
            sv.reflectScrolledClipView(sv.contentView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.gutter = gutter
        guard let tv = scrollView.documentView as? NSTextView else { return }

        // Tab switch: the same persistent text view is being pointed at a
        // different buffer. Save the outgoing buffer's scroll + cursor, swap
        // in the new content, then restore the new buffer's position. No view
        // is recreated, so nothing dangles and state is preserved.
        if coord.buffer.url != buffer.url {
            coord.buffer.savedSelection = tv.selectedRange()
            coord.buffer.savedScrollOrigin = scrollView.contentView.bounds.origin

            coord.buffer = buffer
            tv.string = buffer.text
            if let storage = tv.textStorage {
                HighlighterRegistry.highlighter(for: buffer.url).highlight(storage: storage)
            }
            // Undo history doesn't carry across files (ranges wouldn't match).
            coord.editorUndoManager.removeAllActions()

            let sel = buffer.savedSelection
            let origin = buffer.savedScrollOrigin
            let len = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
            Task { @MainActor [weak scrollView, weak tv] in
                guard let sv = scrollView, tv != nil else { return }
                sv.contentView.scroll(to: origin)
                sv.reflectScrolledClipView(sv.contentView)
                coord.scheduleRecompute()
            }
            return
        }

        coord.buffer = buffer
        // Same buffer, but text changed underneath us (e.g. external reload).
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
        var lsp: LSPClient?
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        /// A dedicated undo manager per editor. Without this, undo actions
        /// register against the window's shared manager and outlive the
        /// NSTextView (which we recreate on every tab switch via `.id`),
        /// so a later ⌘Z invokes a text operation on a freed view → crash.
        let editorUndoManager = UndoManager()

        /// Completion words from the last clangd query (consumed by the
        /// native completion list).
        private var completionWords: [String] = []
        private static let cFamily: Set<String> = ["c", "h", "cpp", "cc", "cxx", "hpp", "hh", "hxx"]

        init(buffer: TextBuffer, gutter: GutterState, lsp: LSPClient?) {
            self.buffer = buffer
            self.gutter = gutter
            self.lsp = lsp
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            editorUndoManager.removeAllActions()
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            editorUndoManager
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
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(selectionDidChange(_:)),
                name: NSTextView.didChangeSelectionNotification,
                object: textView
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

        @objc private func selectionDidChange(_ note: Notification) {
            guard let tv = textView else { return }
            buffer.savedSelection = tv.selectedRange()
        }

        @objc private func boundsDidChange(_ note: Notification) {
            // Save scroll position so it's restored when switching back to this tab.
            if let sv = scrollView {
                buffer.savedScrollOrigin = sv.contentView.bounds.origin
            }
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
            // Auto-offer completion right after a member-access dot.
            let loc = tv.selectedRange().location
            if loc > 0 {
                let s = tv.string as NSString
                if s.character(at: loc - 1) == unichar(46) /* '.' */ {
                    triggerCompletion()
                }
            }
        }

        // MARK: - Completion (clangd)

        /// Intercept the Escape / F5 "complete:" command so manual completion
        /// uses clangd instead of the built-in dictionary.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSTextView.complete(_:)) {
                triggerCompletion()
                return true
            }
            return false
        }

        /// Feed clangd's words into the native completion list, filtered by the
        /// partial word the user is on.
        func textView(_ textView: NSTextView,
                      completions words: [String],
                      forPartialWordRange charRange: NSRange,
                      indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let partial = (textView.string as NSString).substring(with: charRange)
            guard !partial.isEmpty else { return completionWords }
            let lower = partial.lowercased()
            let filtered = completionWords.filter { $0.lowercased().hasPrefix(lower) }
            return filtered.isEmpty ? completionWords : filtered
        }

        private func triggerCompletion() {
            guard let tv = textView, let lsp,
                  Self.cFamily.contains(buffer.url.pathExtension.lowercased()) else { return }
            let location = tv.selectedRange().location
            let position = lspPosition(for: location, in: tv.string as NSString)
            let url = buffer.url
            Task { @MainActor [weak self] in
                guard let self, let list = await lsp.completion(at: position, in: url),
                      !list.items.isEmpty else { return }
                var seen = Set<String>()
                var words: [String] = []
                for item in list.items {
                    let w = item.insertText ?? item.label
                    guard !w.isEmpty, !seen.contains(w) else { continue }
                    seen.insert(w)
                    words.append(w)
                }
                self.completionWords = Array(words.prefix(200))
                guard !self.completionWords.isEmpty, self.textView === tv else { return }
                tv.complete(nil)
            }
        }

        /// Convert a UTF-16 offset into a 0-based LSP line/character position.
        private func lspPosition(for location: Int, in s: NSString) -> LSP.Position {
            var line = 0, lineStart = 0
            var i = 0
            let limit = min(location, s.length)
            while i < limit {
                if s.character(at: i) == unichar(10) { line += 1; lineStart = i + 1 }
                i += 1
            }
            return LSP.Position(line: line, character: location - lineStart)
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
