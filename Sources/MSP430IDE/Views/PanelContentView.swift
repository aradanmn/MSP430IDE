import SwiftUI

/// The single PanelID -> content view mapping, used by DockRegionView,
/// FloatingGroupView and TearLivePreview (previously three copies). To add
/// a panel: add the case here, plus PanelID and PanelManager's defaults.
struct PanelContentView: View {
    let id: PanelID

    var body: some View {
        switch id {
        case .console:        ConsoleView()
        case .problems:       ProblemsView()
        case .fileTree:       FileTreeView()
        case .debugger:       DebuggerView()
        case .courseProgress: CourseProgressView()
        }
    }
}
