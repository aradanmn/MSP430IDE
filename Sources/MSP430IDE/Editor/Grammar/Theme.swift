import AppKit

/// Maps TextMate scope selectors to NSColors.
///
/// Resolution rule: longest matching prefix wins. So a token with scope
/// `keyword.control.c` will match `keyword.control` over the more generic
/// `keyword`. If no rule matches, the default foreground is used.
struct Theme {
    struct Rule {
        let scopePrefix: String
        let color: NSColor
        let bold: Bool

        init(_ scopePrefix: String, color: NSColor, bold: Bool = false) {
            self.scopePrefix = scopePrefix
            self.color = color
            self.bold = bold
        }
    }

    let defaultColor: NSColor
    let rules: [Rule]

    func style(for scopes: [String]) -> (color: NSColor, bold: Bool) {
        var best: (Rule, Int)? = nil  // (rule, prefix-length)
        for scope in scopes {
            for rule in rules {
                if scope == rule.scopePrefix || scope.hasPrefix(rule.scopePrefix + ".") {
                    let length = rule.scopePrefix.count
                    if best == nil || length > best!.1 {
                        best = (rule, length)
                    }
                }
            }
        }
        if let best {
            return (best.0.color, best.0.bold)
        }
        return (defaultColor, false)
    }

    static let `default`: Theme = Theme(
        defaultColor: NSColor.labelColor,
        rules: [
            // Comments
            Rule("comment", color: NSColor.systemGreen),
            Rule("punctuation.definition.comment", color: NSColor.systemGreen),

            // Strings
            Rule("string", color: NSColor.systemRed),
            Rule("string.regexp", color: NSColor.systemRed),
            Rule("punctuation.definition.string", color: NSColor.systemRed),
            Rule("constant.character.escape", color: NSColor.systemOrange),

            // Numbers + constants
            Rule("constant.numeric", color: NSColor.systemOrange),
            Rule("constant.language", color: NSColor.systemPink, bold: true),
            Rule("constant.other", color: NSColor.systemOrange),
            Rule("constant", color: NSColor.systemOrange),

            // Keywords
            Rule("keyword", color: NSColor.systemPink, bold: true),
            Rule("keyword.control", color: NSColor.systemPink, bold: true),
            Rule("keyword.operator", color: NSColor.labelColor),
            Rule("storage", color: NSColor.systemPink, bold: true),
            Rule("storage.type", color: NSColor.systemPink, bold: true),
            Rule("storage.modifier", color: NSColor.systemPink, bold: true),

            // Types
            Rule("entity.name.type", color: NSColor.systemTeal),
            Rule("entity.name.class", color: NSColor.systemTeal),
            Rule("support.type", color: NSColor.systemTeal),
            Rule("support.class", color: NSColor.systemTeal),

            // Functions / labels
            Rule("entity.name.function", color: NSColor.systemBlue),
            Rule("entity.name.label", color: NSColor.systemBlue, bold: true),
            Rule("support.function", color: NSColor.systemBlue),
            Rule("meta.function-call", color: NSColor.systemBlue),

            // Variables
            Rule("variable.parameter", color: NSColor.labelColor),
            Rule("variable.language", color: NSColor.systemPink, bold: true),
            Rule("variable.other.register", color: NSColor.systemTeal),

            // Preprocessor / directives
            Rule("meta.preprocessor", color: NSColor.systemPurple, bold: true),
            Rule("keyword.control.directive", color: NSColor.systemPurple, bold: true),
            Rule("keyword.directive", color: NSColor.systemPurple, bold: true),

            // Section headers (TOML/INI)
            Rule("entity.name.section", color: NSColor.systemPurple, bold: true),
            Rule("entity.name.tag", color: NSColor.systemPurple),

            // Punctuation
            Rule("punctuation", color: NSColor.secondaryLabelColor)
        ]
    )
}
