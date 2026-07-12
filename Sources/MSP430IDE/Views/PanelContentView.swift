import SwiftUI

/// Single source of truth for mapping a PanelID to its content view.
/// Used by DockRegionView, FloatingGroupView, and TearLivePreview.
/// To add a new panel: add the case here (and to PanelID + PanelManager defaults).
struct PanelContentView: View {
    let id: PanelID
    var body: some View {
        switch id {
        case .console:  ConsoleView()
        case .problems: ProblemsView()
        case .fileTree: FileTreeView()
        case .debugger: DebuggerView()
        }
    }
}
