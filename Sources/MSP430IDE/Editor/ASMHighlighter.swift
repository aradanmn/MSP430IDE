import AppKit

/// Hand-rolled MSP430 assembly highlighter.
/// Covers: `;` comments, mnemonics (MOV/JNZ/etc.), registers (R0-R15/SR/SP/PC/CG),
/// directives (.text/.global/.word/.equ/.section/.L*), labels, immediates (#…),
/// addresses (&…), strings, identifiers.
struct ASMHighlighter: Highlighter {
    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)

    // MSP430 instruction set (subset that covers most code).
    private static let mnemonics: Set<String> = [
        // Double-operand
        "mov", "add", "addc", "sub", "subc", "cmp", "dadd", "bit", "bic", "bis",
        "xor", "and",
        // Single-operand
        "rrc", "swpb", "rra", "sxt", "push", "call", "reti",
        // Jumps
        "jne", "jnz", "jeq", "jz", "jnc", "jlo", "jc", "jhs", "jn", "jge", "jl", "jmp",
        // Emulated
        "nop", "ret", "clr", "clrc", "clrn", "clrz", "dec", "decd", "inc", "incd",
        "inv", "pop", "rla", "rlc", "sbc", "setc", "setn", "setz", "tst", "br",
        "adc", "dadc", "eint", "dint"
    ]

    private static let registers: Set<String> = [
        "r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7",
        "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15",
        "pc", "sp", "sr", "cg", "cg1", "cg2"
    ]

    private static let directiveRegex = try? NSRegularExpression(
        pattern: #"^\s*\.[A-Za-z_][A-Za-z0-9_]*"#,
        options: [.anchorsMatchLines]
    )
    private static let labelRegex = try? NSRegularExpression(
        pattern: #"^[A-Za-z_\.][A-Za-z0-9_\.]*:"#,
        options: [.anchorsMatchLines]
    )
    private static let commentRegex = try? NSRegularExpression(
        pattern: #";[^\n]*"#,
        options: []
    )
    private static let stringRegex = try? NSRegularExpression(
        pattern: #""(\\.|[^"\\])*""#,
        options: []
    )
    private static let immediateRegex = try? NSRegularExpression(
        pattern: #"#(-?0x[0-9A-Fa-f]+|-?\d+|\(?[A-Za-z_][A-Za-z0-9_]*\)?)"#,
        options: []
    )
    private static let addressRegex = try? NSRegularExpression(
        pattern: #"&[A-Za-z_][A-Za-z0-9_]*"#,
        options: []
    )
    private static let numberRegex = try? NSRegularExpression(
        pattern: #"\b(0x[0-9A-Fa-f]+|0b[01]+|\d+)\b"#,
        options: []
    )
    private static let identifierRegex = try? NSRegularExpression(
        pattern: #"\b[A-Za-z_][A-Za-z0-9_]*(\.[bw])?\b"#,
        options: []
    )
    private static let preprocessorRegex = try? NSRegularExpression(
        pattern: #"^\s*#\s*\w+"#,
        options: [.anchorsMatchLines]
    )

    func highlight(storage: NSTextStorage) {
        let string = storage.string
        let length = (string as NSString).length
        guard length > 0 else { return }
        let full = NSRange(location: 0, length: length)

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        storage.addAttribute(.font, value: Self.baseFont, range: full)

        let mnemonicColor = NSColor.systemPink
        let registerColor = NSColor.systemTeal
        let directiveColor = NSColor.systemPurple
        let labelColor = NSColor.systemBlue
        let commentColor = NSColor.systemGreen
        let stringColor = NSColor.systemRed
        let immediateColor = NSColor.systemOrange
        let numberColor = NSColor.systemOrange
        let prepColor = NSColor.systemPurple

        // Apply mnemonics + registers by identifier scan (case-insensitive match against sets)
        if let regex = Self.identifierRegex {
            regex.enumerateMatches(in: string, options: [], range: full) { match, _, _ in
                guard let r = match?.range else { return }
                let token = (string as NSString).substring(with: r).lowercased()
                let bare = token.split(separator: ".").first.map(String.init) ?? token
                if Self.mnemonics.contains(bare) {
                    storage.addAttribute(.foregroundColor, value: mnemonicColor, range: r)
                    storage.addAttribute(.font, value: Self.boldFont, range: r)
                } else if Self.registers.contains(token) {
                    storage.addAttribute(.foregroundColor, value: registerColor, range: r)
                }
            }
        }

        apply(Self.numberRegex, string: string, range: full, storage: storage, color: numberColor)
        apply(Self.immediateRegex, string: string, range: full, storage: storage, color: immediateColor)
        apply(Self.addressRegex, string: string, range: full, storage: storage, color: registerColor)
        apply(Self.labelRegex, string: string, range: full, storage: storage, color: labelColor, bold: true)
        apply(Self.directiveRegex, string: string, range: full, storage: storage, color: directiveColor)
        apply(Self.preprocessorRegex, string: string, range: full, storage: storage, color: prepColor, bold: true)
        apply(Self.stringRegex, string: string, range: full, storage: storage, color: stringColor)
        // Comments last so they win over any in-comment identifier hits.
        apply(Self.commentRegex, string: string, range: full, storage: storage, color: commentColor)
    }

    private func apply(_ regex: NSRegularExpression?, string: String, range: NSRange, storage: NSTextStorage, color: NSColor, bold: Bool = false) {
        guard let regex else { return }
        regex.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
            guard let r = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: color, range: r)
            if bold {
                storage.addAttribute(.font, value: Self.boldFont, range: r)
            }
        }
    }
}
