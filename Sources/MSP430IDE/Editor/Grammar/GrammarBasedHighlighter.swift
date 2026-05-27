import AppKit

/// Highlighter that drives display from a TextMate grammar + a theme,
/// rather than from Swift code. Adding language support = drop a
/// `.tmLanguage.json` in a `Grammars/` directory — no code edits.
struct GrammarBasedHighlighter: Highlighter {
    let grammar: TMGrammar
    let theme: Theme

    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)

    func highlight(storage: NSTextStorage) {
        let length = (storage.string as NSString).length
        guard length > 0 else { return }
        let full = NSRange(location: 0, length: length)

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.addAttribute(.foregroundColor, value: theme.defaultColor, range: full)
        storage.addAttribute(.font, value: Self.baseFont, range: full)

        let tokens = TMEngine.tokenize(text: storage.string, grammar: grammar)
        for token in tokens {
            let style = theme.style(for: token.scopes)
            storage.addAttribute(.foregroundColor, value: style.color, range: token.range)
            if style.bold {
                storage.addAttribute(.font, value: Self.boldFont, range: token.range)
            }
        }
    }
}
