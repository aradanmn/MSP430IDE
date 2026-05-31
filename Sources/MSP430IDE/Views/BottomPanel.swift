import SwiftUI
import AppKit

/// Tabbed container for the bottom panel. Today: Console + Problems.
/// Future: more tabs (Serial, Output), draggable to other dock zones,
/// poppable to floating windows. See PanelManager for the extension
/// seams (`bottomTabs`, `floatingPanels`, `location(for:)` to come).
struct BottomPanel: View {
    @EnvironmentObject var panels: PanelManager

    var body: some View {
        VStack(spacing: 0) {
            TabStrip()
            Group {
                if panels.bottomTabs.isEmpty {
                    floatedAwayState
                } else {
                    switch panels.activeBottomTab {
                    case .console:  ConsoleView()
                    case .problems: ProblemsView()
                    default:        Color(nsColor: .textBackgroundColor)
                    }
                }
            }
        }
    }

    private var floatedAwayState: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Panels are open in separate windows")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct TabStrip: View {
    @EnvironmentObject var panels: PanelManager
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(panels.bottomTabs) { id in
                TabButton(id: id)
            }
            Spacer(minLength: 8)
            if !panels.bottomTabs.isEmpty {
                Button {
                    panels.popOut(panels.activeBottomTab)
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 8)
                .help("Open “\(panels.activeBottomTab.title)” in a new window")
            }
            Button {
                appState.clearConsole()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 10)
            .help("Clear console + diagnostics")
        }
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }
}

private struct TabButton: View {
    let id: PanelID
    @EnvironmentObject var panels: PanelManager
    @EnvironmentObject var appState: AppState
    @State private var hovering = false
    @State private var torn = false

    var body: some View {
        let active = panels.isActiveBottom(id)
        Button {
            panels.showPanel(id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: id.systemImage)
                    .font(.caption)
                    .foregroundStyle(active ? .primary : .secondary)
                Text(id.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(active ? .primary : .secondary)
                if id == .problems {
                    DiagnosticCountBadge()
                }
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
                if active {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // Tear-off: drag a tab away from the strip. A translucent preview
        // follows the cursor; the real window is only placed on release.
        // minimumDistance keeps plain clicks working as tab selection.
        .simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .global)
                .onChanged { value in
                    let pulledAway = value.translation.height > 22 || abs(value.translation.width) > 80
                    if !torn && pulledAway {
                        torn = true
                        panels.beginTearPreview(id)
                    }
                    if torn {
                        panels.moveTearPreview(to: NSEvent.mouseLocation)
                    }
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

private struct DiagnosticCountBadge: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        let errors = appState.diagnosticsInOrder.filter { $0.severity == .error }.count
        let warnings = appState.diagnosticsInOrder.filter { $0.severity == .warning }.count
        HStack(spacing: 3) {
            if errors > 0 {
                badgeText("\(errors)", color: .red)
            }
            if warnings > 0 {
                badgeText("\(warnings)", color: .yellow)
            }
        }
    }

    private func badgeText(_ s: String, color: Color) -> some View {
        Text(s)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color == .yellow ? Color.black : Color.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color))
    }
}
