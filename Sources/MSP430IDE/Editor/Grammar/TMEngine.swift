import Foundation

/// Tokenizes text against a TextMate grammar.
///
/// Algorithm: maintain a scope stack and a position cursor. At each step,
/// scan the active pattern set (the top of the stack's `patterns` + the
/// active end-pattern) for the earliest match starting at or after the
/// cursor. Emit tokens for the match plus any sub-captures, then advance.
/// Entering a `begin`/`end` pattern pushes a new context; matching the
/// `end` pattern pops it.
enum TMEngine {
    static func tokenize(text: String, grammar: TMGrammar) -> [TMToken] {
        let nsString = text as NSString
        let fullLength = nsString.length
        let rootScopes = [grammar.scopeName].compactMap { $0 }
        var stack: [Context] = [Context(
            patterns: resolvedPatterns(grammar.patterns ?? [], grammar: grammar),
            endRegex: nil,
            endCaptures: nil,
            contentScopes: rootScopes,
            popScope: nil
        )]
        var tokens: [TMToken] = []
        var pos = 0
        // Bound iterations so a buggy grammar can't hang the editor.
        let maxIter = max(fullLength * 8, 50_000)
        var iter = 0

        while pos < fullLength {
            iter += 1
            if iter > maxIter { break }

            guard let ctx = stack.last else { break }

            // Find earliest match among context patterns + the end pattern (if any).
            var bestPatternIdx: Int? = nil
            var bestPatternMatch: NSTextCheckingResult? = nil
            var bestEndMatch: NSTextCheckingResult? = nil

            for (i, pat) in ctx.patterns.enumerated() {
                if let regex = pat.matchRegex,
                   let m = regex.firstMatch(in: text, options: [], range: NSRange(location: pos, length: fullLength - pos)),
                   m.range.location != NSNotFound {
                    if bestPatternMatch == nil || m.range.location < bestPatternMatch!.range.location {
                        bestPatternMatch = m
                        bestPatternIdx = i
                        bestEndMatch = nil
                    }
                }
            }

            if let endRegex = ctx.endRegex,
               let m = endRegex.firstMatch(in: text, options: [], range: NSRange(location: pos, length: fullLength - pos)),
               m.range.location != NSNotFound {
                if bestPatternMatch == nil || m.range.location < bestPatternMatch!.range.location {
                    bestEndMatch = m
                    bestPatternMatch = nil
                    bestPatternIdx = nil
                }
            }

            // Nothing matched — advance past remaining text.
            if bestPatternMatch == nil && bestEndMatch == nil {
                pos = fullLength
                break
            }

            // End pattern wins → emit any sub-captures + the end range, then pop.
            if let endMatch = bestEndMatch {
                if endMatch.range.location > pos {
                    // The text between pos and endMatch.location stays in the
                    // current contentScopes (we don't emit a token for it; the
                    // caller can color residual unscoped text however it likes).
                }
                emitCaptures(endMatch, captures: ctx.endCaptures, text: text, scopes: ctx.contentScopes, tokens: &tokens)
                pos = max(endMatch.range.upperBound, pos + 1)
                stack.removeLast()
                continue
            }

            // A pattern matched.
            guard let i = bestPatternIdx, let m = bestPatternMatch else {
                pos += 1
                continue
            }
            let resolved = ctx.patterns[i]

            if resolved.kind == .match {
                let combinedScopes = ctx.contentScopes + [resolved.pattern.name].compactMap { $0 }
                if m.range.length > 0 {
                    tokens.append(TMToken(range: m.range, scopes: combinedScopes))
                }
                emitCaptures(m, captures: resolved.pattern.captures, text: text, scopes: combinedScopes, tokens: &tokens)
                pos = max(m.range.upperBound, pos + 1)
            } else {
                // begin/end block
                let outerScopes = ctx.contentScopes
                let blockScopes = outerScopes + [resolved.pattern.name].compactMap { $0 }
                let contentScopes = blockScopes + [resolved.pattern.contentName].compactMap { $0 }
                if m.range.length > 0 {
                    tokens.append(TMToken(range: m.range, scopes: blockScopes))
                }
                emitCaptures(m, captures: resolved.pattern.beginCaptures ?? resolved.pattern.captures, text: text, scopes: blockScopes, tokens: &tokens)
                let endRegex = resolved.compiledEndRegex(for: m, in: text, grammar: resolved.parentGrammar)
                stack.append(Context(
                    patterns: resolved.innerPatterns,
                    endRegex: endRegex,
                    endCaptures: resolved.pattern.endCaptures ?? resolved.pattern.captures,
                    contentScopes: contentScopes,
                    popScope: resolved.pattern.name
                ))
                pos = max(m.range.upperBound, pos + 1)
            }
        }

        // Sort + dedupe (the engine can emit overlapping tokens; later passes
        // should take the last token for any byte).
        return tokens.sorted { $0.range.location < $1.range.location }
    }

    // MARK: - Capture emission

    private static func emitCaptures(_ match: NSTextCheckingResult, captures: [String: TMCapture]?, text: String, scopes: [String], tokens: inout [TMToken]) {
        guard let captures, !captures.isEmpty else { return }
        for (key, capture) in captures {
            guard let idx = Int(key), idx < match.numberOfRanges else { continue }
            let range = match.range(at: idx)
            guard range.location != NSNotFound, range.length > 0 else { continue }
            let combined = scopes + [capture.name].compactMap { $0 }
            if !combined.isEmpty {
                tokens.append(TMToken(range: range, scopes: combined))
            }
        }
    }

    // MARK: - Pattern resolution

    private struct Context {
        let patterns: [ResolvedPattern]
        let endRegex: NSRegularExpression?
        let endCaptures: [String: TMCapture]?
        let contentScopes: [String]
        let popScope: String?
    }

    enum PatternKind {
        case match
        case beginEnd
    }

    final class ResolvedPattern {
        let pattern: TMPattern
        let matchRegex: NSRegularExpression?
        let beginRegex: NSRegularExpression?
        let endTemplate: String?
        let innerPatterns: [ResolvedPattern]
        let parentGrammar: TMGrammar?

        init(pattern: TMPattern,
             matchRegex: NSRegularExpression?,
             beginRegex: NSRegularExpression?,
             endTemplate: String?,
             innerPatterns: [ResolvedPattern],
             parentGrammar: TMGrammar?) {
            self.pattern = pattern
            self.matchRegex = matchRegex
            self.beginRegex = beginRegex
            self.endTemplate = endTemplate
            self.innerPatterns = innerPatterns
            self.parentGrammar = parentGrammar
        }

        var kind: PatternKind { matchRegex != nil ? .match : .beginEnd }

        func compiledEndRegex(for beginMatch: NSTextCheckingResult, in text: String, grammar: TMGrammar?) -> NSRegularExpression? {
            guard let endTemplate else { return nil }
            // Replace \1, \2, ... with the corresponding capture groups from beginMatch.
            let nsString = text as NSString
            var result = ""
            var i = endTemplate.startIndex
            while i < endTemplate.endIndex {
                let c = endTemplate[i]
                if c == "\\", endTemplate.index(after: i) < endTemplate.endIndex {
                    let next = endTemplate[endTemplate.index(after: i)]
                    if let digit = next.wholeNumberValue, digit > 0, digit < beginMatch.numberOfRanges {
                        let r = beginMatch.range(at: digit)
                        if r.location != NSNotFound {
                            result += NSRegularExpression.escapedPattern(for: nsString.substring(with: r))
                        }
                        i = endTemplate.index(i, offsetBy: 2)
                        continue
                    }
                }
                result.append(c)
                i = endTemplate.index(after: i)
            }
            return try? NSRegularExpression(pattern: result, options: [])
        }
    }

    static func resolvedPatterns(_ patterns: [TMPattern], grammar: TMGrammar) -> [ResolvedPattern] {
        var out: [ResolvedPattern] = []
        for p in patterns {
            if p.disabled == 1 { continue }
            if let include = p.include {
                let resolved = resolveInclude(include, grammar: grammar)
                out.append(contentsOf: resolvedPatterns(resolved, grammar: grammar))
                continue
            }
            if let match = p.match {
                let regex = try? NSRegularExpression(pattern: match, options: [])
                out.append(ResolvedPattern(
                    pattern: p,
                    matchRegex: regex,
                    beginRegex: nil,
                    endTemplate: nil,
                    innerPatterns: [],
                    parentGrammar: grammar
                ))
            } else if let begin = p.begin {
                let regex = try? NSRegularExpression(pattern: begin, options: [])
                let inner = resolvedPatterns(p.patterns ?? [], grammar: grammar)
                out.append(ResolvedPattern(
                    pattern: p,
                    matchRegex: nil,
                    beginRegex: regex,
                    endTemplate: p.end,
                    innerPatterns: inner,
                    parentGrammar: grammar
                ))
            }
        }
        return out
    }

    private static func resolveInclude(_ include: String, grammar: TMGrammar) -> [TMPattern] {
        if include == "$self" || include == "$base" {
            return grammar.patterns ?? []
        }
        if include.hasPrefix("#") {
            let key = String(include.dropFirst())
            if let entry = grammar.repository?[key] {
                if let nested = entry.patterns, entry.match == nil, entry.begin == nil {
                    return nested
                }
                return [entry]
            }
        }
        return []
    }
}
