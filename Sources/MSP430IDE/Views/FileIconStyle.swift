import SwiftUI

/// One file-type icon table for the tab bar and the file tree (previously
/// two copies that had drifted: tabs lacked md/toml/json/ld/html icons).
extension URL {
    var fileIconName: String {
        switch pathExtension.lowercased() {
        case "c":                        return "c.square"
        case "h":                        return "h.square"
        case "s", "asm":                 return "s.square"
        case "md", "markdown", "mdown":  return "doc.richtext"
        case "txt", "text":              return "doc.plaintext"
        case "toml":                     return "doc.badge.gearshape"
        case "json":                     return "curlybraces"
        case "ld":                       return "memorychip"
        case "html", "svg":              return "play.rectangle.fill"
        default:                         return "doc"
        }
    }

    var fileIconColor: Color {
        switch pathExtension.lowercased() {
        case "c":                        return .blue
        case "h":                        return .purple
        case "s", "asm":                 return .orange
        case "md", "markdown", "mdown":  return .green
        case "toml":                     return .brown
        case "json":                     return .yellow
        case "ld":                       return .pink
        case "html", "svg":              return .teal
        default:                         return .secondary
        }
    }
}
