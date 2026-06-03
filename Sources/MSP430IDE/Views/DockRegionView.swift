import SwiftUI
import AppKit

/// A dock region at one edge of the main window. Shows its panels as tabs
/// (tear a tab out to float / re-dock elsewhere) and the active panel below.
struct DockRegionView: View {
    let edge: DockEdge
    @EnvironmentObject var panels: PanelManager
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider()
            Group {
                switch panels.activePanel(at: edge) {
                case .console:  ConsoleView()
                case .problems: ProblemsView()
                case .fileTree: FileTreeView()
                case .debugger: DebuggerView()
                case .none:     Color(nsColor: .textBackgroundColor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(panels.dockedPanels(at: edge)) { id in
                DockTab(edge: edge, id: id)
            }
            Spacer(minLength: 8)
            if edge == .bottom, panels.dockedPanels(at: edge).contains(where: { $0 == .console || $0 == .problems }) {
                Button {
                    appState.clearConsole()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 10)
                .help("Clear console + diagnostics")
            }
        }
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
    }
}

private struct DockTab: View {
    let edge: DockEdge
    let id: PanelID
    @EnvironmentObject var panels: PanelManager
    @EnvironmentObject var appState: AppState
    @State private var hovering = false
    @State private var torn = false

    var body: some View {
        let active = panels.isActive(id, at: edge)
        Button {
            panels.selectDocked(id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: id.systemImage)
                    .font(.caption)
                    .foregroundStyle(active ? .primary : .secondary)
                Text(id.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(active ? .primary : .secondary)
                if id == .problems { DiagnosticCountBadge() }
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background {
                if active {
                    Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
                } else if hovering {
                    Color(nsColor: .windowBackgroundColor).opacity(0.5)
                }
            }
            .overlay(alignment: .bottom) {
                if active { Rectangle().fill(Color.accentColor).frame(height: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .global)
                .onChanged { value in
                    if !torn && (abs(value.translation.height) > 22 || abs(value.translation.width) > 60) {
                        torn = true
                        panels.beginTearPreview(id)
                    }
                    if torn { panels.moveTearPreview(to: NSEvent.mouseLocation) }
                }
                .onEnded { _ in
                    if torn {
                        panels.endTear(commit: true, id: id, at: NSEvent.mouseLocation)
                        torn = false
                    }
                }
        )
    }
}

/// Error/warning count chips for the Issues tab.
struct DiagnosticCountBadge: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        let errors = appState.diagnosticsInOrder.filter { $0.severity == .error }.count
        let warnings = appState.diagnosticsInOrder.filter { $0.severity == .warning }.count
        HStack(spacing: 3) {
            if errors > 0 { badge("\(errors)", color: .red) }
            if warnings > 0 { badge("\(warnings)", color: .yellow) }
        }
    }

    private func badge(_ s: String, color: Color) -> some View {
        Text(s)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color == .yellow ? Color.black : Color.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color))
    }
}
