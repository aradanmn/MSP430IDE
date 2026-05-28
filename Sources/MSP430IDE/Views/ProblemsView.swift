import SwiftUI

/// The "Problems" tab in the bottom panel. Lists every diagnostic from
/// the most recent build with click-to-jump behavior. Designed to also
/// work standalone if/when the panel is popped out into a floating
/// window (it only needs `AppState` from the environment).
struct ProblemsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.diagnosticsInOrder.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appState.diagnosticsInOrder) { diag in
                            DiagnosticRow(diag: diag)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No problems")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DiagnosticRow: View {
    let diag: Diagnostic
    @EnvironmentObject var appState: AppState
    @State private var hovering = false

    var body: some View {
        Button {
            appState.jumpTo(diagnostic: diag)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(color)
                    .font(.caption)
                Text(location)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(diag.message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var location: String {
        let rel = relativePath
        if let col = diag.column {
            return "\(rel):\(diag.line):\(col)"
        }
        return "\(rel):\(diag.line)"
    }

    private var relativePath: String {
        guard let root = appState.workspaceRoot else { return diag.file.lastPathComponent }
        let prefix = root.path + "/"
        if diag.file.path.hasPrefix(prefix) {
            return String(diag.file.path.dropFirst(prefix.count))
        }
        return diag.file.lastPathComponent
    }

    private var iconName: String {
        switch diag.severity {
        case .error:   return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .note:    return "info.circle.fill"
        }
    }

    private var color: Color {
        switch diag.severity {
        case .error:   return .red
        case .warning: return .orange
        case .note:    return .blue
        }
    }
}
