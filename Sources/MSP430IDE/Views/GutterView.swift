import SwiftUI
import AppKit

final class GutterState: ObservableObject {
    struct VisibleLine: Identifiable, Equatable {
        let number: Int
        let y: CGFloat
        var id: Int { number }
    }

    @Published var visibleLines: [VisibleLine] = []
    @Published var totalLines: Int = 1

    var width: CGFloat {
        let digits = max(2, String(totalLines).count)
        return CGFloat(digits) * 8 + 22  // extra room for the diagnostic dot
    }
}

struct GutterView: View {
    @ObservedObject var state: GutterState
    let url: URL?
    @EnvironmentObject var appState: AppState

    var body: some View {
        let diagMap = diagnosticsByLine
        ZStack(alignment: .topLeading) {
            Color(nsColor: .textBackgroundColor)

            ForEach(state.visibleLines) { line in
                let sev = diagMap[line.number]
                ZStack(alignment: .leading) {
                    if let sev {
                        Image(systemName: gutterIcon(for: sev))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(color(for: sev))
                            .frame(width: 12, height: 12)
                            .padding(.leading, 2)
                            .help(diagMessage(line: line.number))
                    }
                    Text("\(line.number)")
                        .font(.system(size: 10.5, weight: sev != nil ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(sev != nil ? color(for: sev!) : Color(nsColor: .tertiaryLabelColor))
                        .monospacedDigit()
                        .frame(width: state.width - 6, alignment: .trailing)
                }
                .frame(width: state.width)
                .offset(x: 0, y: line.y)
            }
        }
        .frame(maxHeight: .infinity)
        .frame(width: state.width)
        .clipped()
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private var diagnosticsByLine: [Int: Diagnostic.Severity] {
        guard let url, let diags = appState.diagnostics[url] else { return [:] }
        var map: [Int: Diagnostic.Severity] = [:]
        for d in diags {
            let existing = map[d.line]
            // Severity precedence: error > warning > note
            if existing == nil { map[d.line] = d.severity; continue }
            if d.severity == .error { map[d.line] = .error; continue }
            if d.severity == .warning && existing != .error { map[d.line] = .warning }
        }
        return map
    }

    private func diagMessage(line: Int) -> String {
        guard let url, let diags = appState.diagnostics[url] else { return "" }
        return diags.filter { $0.line == line }
            .map { "\($0.severity.rawValue): \($0.message)" }
            .joined(separator: "\n")
    }

    private func gutterIcon(for sev: Diagnostic.Severity) -> String {
        switch sev {
        case .error:   return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .note:    return "info.circle.fill"
        }
    }

    private func color(for sev: Diagnostic.Severity) -> Color {
        switch sev {
        case .error:   return .red
        case .warning: return .yellow
        case .note:    return .blue
        }
    }
}
