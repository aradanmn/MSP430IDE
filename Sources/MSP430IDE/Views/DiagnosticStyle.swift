import SwiftUI

extension Diagnostic.Severity {
    var iconName: String {
        switch self {
        case .error:   return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .note:    return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .error:   return .red
        case .warning: return .yellow
        case .note:    return .blue
        }
    }
}
