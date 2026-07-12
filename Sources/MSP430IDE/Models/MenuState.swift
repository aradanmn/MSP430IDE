import SwiftUI
import Combine

/// The handful of facts the menu bar actually depends on, deduplicated so
/// menus rebuild only when one of them changes.
///
/// AppState publishes constantly (console output, diagnostics, status
/// messages, file-watcher refreshes). If .commands observes AppState
/// directly, every publish re-evaluates the scene body and macOS tears
/// down whichever menu is open — submenus flicker and vanish before they
/// can be clicked. AppCommands observes only this object instead.
final class MenuState: ObservableObject {
    @Published var hasSelectedFile = false
    @Published var hasWorkspace = false
    @Published var hasProject = false
    @Published var buildMode: BuildMode? = nil
    @Published var isBuilding = false
    @Published var isFlashing = false
    @Published var isDebugging = false
    @Published var debugStopped = false
    @Published var openTabCount = 0

    @MainActor
    func bind(to app: AppState) {
        app.$selectedFile.map { $0 != nil }.removeDuplicates().assign(to: &$hasSelectedFile)
        app.$workspaceRoot.map { $0 != nil }.removeDuplicates().assign(to: &$hasWorkspace)
        app.$project.map { $0 != nil }.removeDuplicates().assign(to: &$hasProject)
        app.$project.map { $0?.mode }.removeDuplicates().assign(to: &$buildMode)
        app.$isBuilding.removeDuplicates().assign(to: &$isBuilding)
        app.$isFlashing.removeDuplicates().assign(to: &$isFlashing)
        app.$isDebugging.removeDuplicates().assign(to: &$isDebugging)
        app.$debugSessionState.map { $0 == .stopped }.removeDuplicates().assign(to: &$debugStopped)
        app.editor.$openTabs.map(\.count).removeDuplicates().assign(to: &$openTabCount)
    }
}
