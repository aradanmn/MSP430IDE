import Foundation

/// Single dispatch point for syntax highlighting.
///
/// Resolution: look up the file extension in `GrammarStore`. If a
/// `.tmLanguage.json` grammar is registered for it, return a
/// `GrammarBasedHighlighter` backed by that grammar + the default theme.
/// Otherwise return a `PlainTextHighlighter` (no syntactic coloring).
///
/// **Adding a new language requires no Swift code changes** — drop a
/// `.tmLanguage.json` file in:
///   - the app bundle's `Grammars/` directory (for IDE-shipped grammars), or
///   - `~/Library/Application Support/MSP430IDE/Grammars/` (for user overrides)
/// whose `fileTypes` field lists the extension(s) to handle.
enum HighlighterRegistry {
    static func highlighter(for url: URL) -> Highlighter {
        highlighter(forExtension: url.pathExtension.lowercased())
    }

    static func highlighter(forExtension ext: String) -> Highlighter {
        if let grammar = GrammarStore.shared.grammar(forExtension: ext) {
            return GrammarBasedHighlighter(grammar: grammar, theme: .default)
        }
        return PlainTextHighlighter()
    }
}
