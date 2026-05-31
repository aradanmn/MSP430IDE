import SwiftUI
import AppKit

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

/// Owns runtime layout state for every panel: which bottom tab is active,
/// and which panels are currently torn off into their own desktop windows.
///
/// Pop-out windows host the same SwiftUI panel views (sharing `AppState`
/// and this manager via the environment), so a floating Console reflects
/// live build output exactly like the docked one.
@MainActor
final class PanelManager: ObservableObject {
    @Published var activeBottomTab: PanelID = .console

    /// Panels currently shown as floating windows.
    @Published var floatingPanels: Set<PanelID> = []

    /// Shared app state, injected once at launch so pop-out windows can
    /// carry the same environment objects as the main window.
    weak var appState: AppState?

    private var windowControllers: [PanelID: FloatingPanelWindowController] = [:]

    func attach(appState: AppState) {
        self.appState = appState
    }

    /// Bottom-dock tabs that aren't currently floating.
    var bottomTabs: [PanelID] {
        [.console, .problems].filter { !floatingPanels.contains($0) }
    }

    func isFloating(_ id: PanelID) -> Bool { floatingPanels.contains(id) }

    func isActiveBottom(_ id: PanelID) -> Bool { activeBottomTab == id }

    func showPanel(_ id: PanelID) {
        if floatingPanels.contains(id) {
            windowControllers[id]?.window.makeKeyAndOrderFront(nil)
            return
        }
        if bottomTabs.contains(id) {
            activeBottomTab = id
        }
    }

    // MARK: - Pop-out / dock

    func togglePopOut(_ id: PanelID) {
        if floatingPanels.contains(id) { dockBack(id) } else { popOut(id) }
    }

    func popOut(_ id: PanelID) {
        guard let appState else { return }
        if let existing = windowControllers[id] {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        floatingPanels.insert(id)
        // If the active bottom tab just floated, fall back to a docked one.
        if activeBottomTab == id { activeBottomTab = bottomTabs.first ?? .console }

        let content = FloatingPanelContent(id: id)
            .environmentObject(appState)
            .environmentObject(self)
        let hosting = NSHostingController(rootView: AnyView(content))
        let window = NSWindow(contentViewController: hosting)
        window.title = id.title
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: id == .fileTree ? 280 : 620, height: 380))
        window.center()

        let controller = FloatingPanelWindowController(id: id, window: window, manager: self)
        windowControllers[id] = controller
        window.makeKeyAndOrderFront(nil)
    }

    func dockBack(_ id: PanelID) {
        // Closing triggers windowWillClose → handleWindowClosed.
        windowControllers[id]?.window.close()
    }

    fileprivate func handleWindowClosed(_ id: PanelID) {
        windowControllers[id] = nil
        floatingPanels.remove(id)
        if !bottomTabs.contains(activeBottomTab) {
            activeBottomTab = bottomTabs.first ?? .console
        }
    }
}

/// Retains a pop-out window and re-docks the panel when the window closes.
final class FloatingPanelWindowController: NSObject, NSWindowDelegate {
    let id: PanelID
    let window: NSWindow
    weak var manager: PanelManager?

    init(id: PanelID, window: NSWindow, manager: PanelManager) {
        self.id = id
        self.window = window
        self.manager = manager
        super.init()
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        manager?.handleWindowClosed(id)
    }
}

/// The content shown inside a pop-out window: a small header with a
/// dock-back control, plus the panel itself.
struct FloatingPanelContent: View {
    let id: PanelID
    @EnvironmentObject var panels: PanelManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: id.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(id.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    panels.dockBack(id)
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(.borderless)
                .help("Dock back into the main window")
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 220, minHeight: 160)
    }

    @ViewBuilder
    private var content: some View {
        switch id {
        case .console:  ConsoleView()
        case .problems: ProblemsView()
        case .fileTree: FileTreeView()
        }
    }
}
