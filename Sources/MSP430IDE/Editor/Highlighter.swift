import AppKit

/// A syntax highlighter applies colors/font traits to an NSTextStorage in-place.
/// Implementations: `GrammarBasedHighlighter` (TextMate grammars),
/// `PlainTextHighlighter` (fallback).
protocol Highlighter {
    func highlight(storage: NSTextStorage)
}
