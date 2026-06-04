import SwiftUI

extension URL {
    var fileIconName: String {
        switch pathExtension.lowercased() {
        case "c":               return "c.square"
        case "h":               return "h.square"
        case "s", "asm":        return "s.square"
        case "md", "markdown":  return "doc.richtext"
        case "txt", "text":     return "doc.plaintext"
        case "toml":            return "doc.badge.gearshape"
        case "json":            return "curlybraces"
        case "ld":              return "memorychip"
        default:                return "doc"
        }
    }

    var fileIconColor: Color {
        switch pathExtension.lowercased() {
        case "c":               return .blue
        case "h":               return .purple
        case "s", "asm":        return .orange
        case "md", "markdown":  return .green
        case "toml":            return .brown
        case "json":            return .yellow
        case "ld":              return .pink
        default:                return .secondary
        }
    }
}
