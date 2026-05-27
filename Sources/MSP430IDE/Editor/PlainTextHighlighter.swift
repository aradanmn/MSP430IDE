import AppKit

/// Fallback highlighter used for files we have no specific grammar for
/// (e.g. .md, .txt, .gitignore). Renders text in the system label color
/// with the editor's monospaced font, no syntactic coloring.
struct PlainTextHighlighter: Highlighter {
    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    func highlight(storage: NSTextStorage) {
        let length = (storage.string as NSString).length
        guard length > 0 else { return }
        let full = NSRange(location: 0, length: length)

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        storage.addAttribute(.font, value: Self.baseFont, range: full)
    }
}
