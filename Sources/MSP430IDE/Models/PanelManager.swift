import SwiftUI

/// Identifier for every dockable / detachable panel in the IDE. New
/// panels (e.g. Serial Monitor, Debug Variables) add a case here and
/// teach `BottomPanel` / `MainView` how to render them.
enum PanelID: String, CaseIterable, Identifiable, Hashable, Codable {
    case console
    case problems
    case fileTree
    // Future:
    // case serial
    // case debugVariables
    // case outline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .console:   return "Console"
        case .problems:  return "Issues"
        case .fileTree:  return "Files"
        }
    }

    var systemImage: String {
        switch self {
        case .console:  return "terminal.fill"
        case .problems: return "exclamationmark.triangle.fill"
        case .fileTree: return "folder.fill"
        }
    }
}

/// Owns runtime layout state for every panel.
///
/// **Today**: tracks which tab is active in the bottom panel and which
/// panels are docked. The rest of the IDE only consumes a few simple
/// queries (`activeBottomTab`, `bottomTabs`, `showPanel`), keeping the
/// public surface small.
///
/// **Designed for**: pop-out floating windows, drag-to-snap-dock-zones,
/// multiple stacks per zone. The `floatingPanels` set and
/// `location(for:)` helper are the future seams. See the
/// "Pop-out and snap-to-edge for panels" follow-up task for the full
/// extension plan.
@MainActor
final class PanelManager: ObservableObject {
    @Published var activeBottomTab: PanelID = .console

    /// Panels currently displayed as floating windows. Empty in v1; the
    /// pop-out follow-up will populate this and key secondary
    /// WindowGroups off the same IDs.
    @Published var floatingPanels: Set<PanelID> = []

    /// The ordered tabs that live in the bottom panel. Future:
    /// derived per-zone from a `location(for:)` map. For now, hardcoded.
    var bottomTabs: [PanelID] { [.console, .problems] }

    func isFloating(_ id: PanelID) -> Bool { floatingPanels.contains(id) }

    func isActiveBottom(_ id: PanelID) -> Bool { activeBottomTab == id }

    /// Activate / surface a panel. Today this just switches the bottom
    /// tab when the panel is one of the bottom tabs. Future overrides
    /// will bring floating windows to the front and expand collapsed
    /// dock zones.
    func showPanel(_ id: PanelID) {
        if bottomTabs.contains(id) {
            activeBottomTab = id
        }
        // Future: NSApp.activate floating window, etc.
    }
}
