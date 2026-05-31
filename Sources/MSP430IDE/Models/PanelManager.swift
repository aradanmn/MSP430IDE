import SwiftUI
import AppKit
import Combine

/// Identifier for every dockable / detachable panel in the IDE.
enum PanelID: String, CaseIterable, Identifiable, Hashable, Codable {
    case console
    case problems
    case fileTree

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

/// One floating window's worth of panels, shown as tabs. Tearing a tab out
/// splits the group; dropping a tab onto another window merges into it.
@MainActor
final class FloatingGroup: ObservableObject, Identifiable {
    let id = UUID()
    @Published var panels: [PanelID]
    @Published var active: PanelID

    init(_ panels: [PanelID]) {
        self.panels = panels
        self.active = panels.first ?? .console
    }
}

/// Owns the bottom-dock state and every floating window (each a group of
/// panels). Pop-out windows host the same SwiftUI panel views with the
/// shared `AppState`, so they stay fully live.
@MainActor
final class PanelManager: ObservableObject {
    @Published var activeBottomTab: PanelID = .console

    /// Floating windows, each a group of one or more panels.
    @Published var floatingGroups: [FloatingGroup] = []
    /// Flattened set of panels that are currently floating (drives bottomTabs).
    @Published private(set) var floatingPanels: Set<PanelID> = []

    weak var appState: AppState?
    weak var mainWindow: NSWindow?

    private var groupWindows: [UUID: FloatingPanelWindowController] = [:]
    private var tearPreviewWindow: NSWindow?

    /// Remembered content size of each panel's floating window, so re-popping
    /// (and the tear preview) reuse the size you left it at.
    private var lastFloatingSize: [PanelID: NSSize] = [:]

    private func defaultSize(_ id: PanelID) -> NSSize {
        id == .fileTree ? NSSize(width: 280, height: 480) : NSSize(width: 640, height: 320)
    }

    // Drag-to-dock: track the floating window currently being moved by its
    // title bar, and act on release.
    private var draggedGroupID: UUID?
    private var suppressMoveTracking = false
    private var mouseUpMonitors: [Any] = []

    func attach(appState: AppState) {
        self.appState = appState
        installDragMonitorsIfNeeded()
    }

    func setMainWindow(_ window: NSWindow?) { mainWindow = window }

    // MARK: - Drag-to-dock (grab a floating window by its title bar)

    private func installDragMonitorsIfNeeded() {
        guard mouseUpMonitors.isEmpty else { return }
        // Title-bar window drags run in AppKit's own event loop, so a global
        // monitor reliably catches the release; a local one covers the rest.
        let onUp: () -> Void = { [weak self] in
            Task { @MainActor in self?.handleWindowDragRelease() }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { _ in onUp() }) {
            mouseUpMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { ev in onUp(); return ev }) {
            mouseUpMonitors.append(l)
        }
    }

    fileprivate func noteWindowMoved(_ groupID: UUID) {
        guard !suppressMoveTracking else { return }
        draggedGroupID = groupID
        updateDockHighlight()
    }

    private func handleWindowDragRelease() {
        hideDockHighlight()
        guard let movedID = draggedGroupID else { return }
        draggedGroupID = nil
        let point = NSEvent.mouseLocation

        // Dropped over another floating window → merge into it.
        if let targetID = groupWindows.first(where: { $0.key != movedID && $0.value.window.frame.contains(point) })?.key {
            mergeGroup(movedID, into: targetID)
            return
        }
        // Dropped over the main window → dock its panels back to the bottom.
        if let mw = mainWindow, mw.frame.contains(point) {
            dockGroup(movedID)
        }
    }

    // MARK: - Snap-to-edge dock highlight

    private var dockHighlight: NSWindow?

    /// While a floating window is dragged over the main window, highlight the
    /// dock zone it would snap into (left for the file tree, bottom for
    /// Console/Issues).
    private func updateDockHighlight() {
        guard let movedID = draggedGroupID,
              let group = floatingGroups.first(where: { $0.id == movedID }),
              let mw = mainWindow,
              mw.frame.contains(NSEvent.mouseLocation) else {
            hideDockHighlight()
            return
        }
        showDockHighlight(dockZoneRect(for: group, in: mw.frame))
    }

    private func dockZoneRect(for group: FloatingGroup, in frame: NSRect) -> NSRect {
        if group.panels.contains(.fileTree) {
            return NSRect(x: frame.minX, y: frame.minY, width: 240, height: frame.height)
        }
        let h = frame.height * 0.3   // bottom strip for Console/Issues
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: h)
    }

    private func showDockHighlight(_ rect: NSRect) {
        let window = dockHighlight ?? {
            let w = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
            w.isOpaque = false
            w.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22)
            w.ignoresMouseEvents = true
            w.level = .floating
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            dockHighlight = w
            return w
        }()
        window.setFrame(rect, display: true)
        window.orderFront(nil)
    }

    private func hideDockHighlight() {
        dockHighlight?.orderOut(nil)
    }

    private func mergeGroup(_ sourceID: UUID, into targetID: UUID) {
        guard let source = floatingGroups.first(where: { $0.id == sourceID }),
              let target = floatingGroups.first(where: { $0.id == targetID }),
              source !== target else { return }
        for panel in source.panels where !target.panels.contains(panel) {
            target.panels.append(panel)
        }
        target.active = source.panels.last ?? target.active
        source.panels.removeAll()
        groupWindows[sourceID]?.window.close() // empties → handleWindowClosed
        rebuildFloatingSet()
        groupWindows[targetID]?.window.makeKeyAndOrderFront(nil)
    }

    var bottomTabs: [PanelID] {
        [.console, .problems].filter { !floatingPanels.contains($0) }
    }

    func isFloating(_ id: PanelID) -> Bool { floatingPanels.contains(id) }
    func isActiveBottom(_ id: PanelID) -> Bool { activeBottomTab == id }

    func showPanel(_ id: PanelID) {
        if let group = floatingGroups.first(where: { $0.panels.contains(id) }) {
            group.active = id
            groupWindows[group.id]?.window.makeKeyAndOrderFront(nil)
            return
        }
        if bottomTabs.contains(id) { activeBottomTab = id }
    }

    // MARK: - Pop-out via button

    func popOut(_ id: PanelID) {
        moveToNewGroup(id, at: nil)
    }

    func togglePopOut(_ id: PanelID) {
        if isFloating(id) { dockBack(id) } else { popOut(id) }
    }

    /// Dock a single panel back to the bottom (removing it from its group).
    func dockBack(_ id: PanelID) {
        removeFromCurrentGroup(id)
        rebuildFloatingSet()
        fixActiveBottomTab()
    }

    /// Dock an entire floating group back to the bottom (its window closed).
    func dockGroup(_ groupID: UUID) {
        groupWindows[groupID]?.window.close()
    }

    // MARK: - Tear-off drag preview

    func beginTearPreview(_ id: PanelID) {
        guard tearPreviewWindow == nil, let appState else { return }
        let size = lastFloatingSize[id] ?? defaultSize(id)
        let content = TearLivePreview(id: id)
            .environmentObject(appState)
            .environmentObject(self)
        let hosting = NSHostingController(rootView: AnyView(content))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setContentSize(size)
        window.alphaValue = 0.82
        tearPreviewWindow = window
        window.orderFront(nil)
        moveTearPreview(to: NSEvent.mouseLocation)
    }

    func moveTearPreview(to screenPoint: NSPoint) {
        // Cursor sits near the top of the preview, as if grabbing its title.
        tearPreviewWindow?.setFrameTopLeftPoint(NSPoint(x: screenPoint.x - 40, y: screenPoint.y + 14))
    }

    /// Finish a tear drag. If dropped over another floating window, merge
    /// into it; otherwise pop into a new window at the drop point.
    func endTear(commit: Bool, id: PanelID, at screenPoint: NSPoint) {
        tearPreviewWindow?.orderOut(nil)
        tearPreviewWindow = nil
        guard commit else { return }

        // A floating window (other than the panel's own solo window) under
        // the cursor → merge.
        if let targetID = groupWindows.first(where: { $0.value.window.frame.contains(screenPoint) })?.key,
           let target = floatingGroups.first(where: { $0.id == targetID }) {
            merge(id, into: target)
        } else {
            moveToNewGroup(id, at: screenPoint)
        }
    }

    // MARK: - Group mutations

    private func currentGroup(of id: PanelID) -> FloatingGroup? {
        floatingGroups.first { $0.panels.contains(id) }
    }

    private func merge(_ id: PanelID, into target: FloatingGroup) {
        if currentGroup(of: id) === target {
            target.active = id
            return
        }
        target.panels.append(id)
        target.active = id
        removeFromCurrentGroup(id, except: target)
        rebuildFloatingSet()
        groupWindows[target.id]?.window.makeKeyAndOrderFront(nil)
    }

    private func moveToNewGroup(_ id: PanelID, at screenPoint: NSPoint?) {
        // Already alone in its own window → just reposition that window.
        if let g = currentGroup(of: id), g.panels == [id] {
            if let p = screenPoint {
                suppressMoveTracking = true
                groupWindows[g.id]?.window.setFrameTopLeftPoint(NSPoint(x: p.x - 60, y: p.y + 12))
                suppressMoveTracking = false
            }
            groupWindows[g.id]?.window.makeKeyAndOrderFront(nil)
            return
        }
        removeFromCurrentGroup(id)
        let group = FloatingGroup([id])
        floatingGroups.append(group)
        rebuildFloatingSet()
        openWindow(for: group, at: screenPoint)
    }

    /// Remove `id` from whatever floating group holds it. If that empties the
    /// group, its window is closed. `except` skips a group we're merging into.
    private func removeFromCurrentGroup(_ id: PanelID, except keep: FloatingGroup? = nil) {
        for group in floatingGroups where group !== keep && group.panels.contains(id) {
            group.panels.removeAll { $0 == id }
            if group.panels.isEmpty {
                groupWindows[group.id]?.window.close() // → handleWindowClosed
            } else if group.active == id {
                group.active = group.panels.first!
            }
        }
    }

    private func rebuildFloatingSet() {
        floatingPanels = Set(floatingGroups.flatMap { $0.panels })
        // A panel that just floated must not stay selected in the bottom dock.
        if !bottomTabs.contains(activeBottomTab) {
            activeBottomTab = bottomTabs.first ?? .console
        }
    }

    private func fixActiveBottomTab() {
        if !bottomTabs.contains(activeBottomTab) {
            activeBottomTab = bottomTabs.first ?? .console
        }
    }

    private func openWindow(for group: FloatingGroup, at screenPoint: NSPoint?) {
        guard let appState else { return }
        let content = FloatingGroupView(group: group)
            .environmentObject(appState)
            .environmentObject(self)
        let hosting = NSHostingController(rootView: AnyView(content))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.backgroundColor = .textBackgroundColor
        window.setContentSize(lastFloatingSize[group.active] ?? defaultSize(group.active))
        suppressMoveTracking = true
        if let p = screenPoint {
            window.setFrameTopLeftPoint(NSPoint(x: p.x - 60, y: p.y + 12))
        } else {
            window.center()
        }
        suppressMoveTracking = false
        let controller = FloatingPanelWindowController(group: group, window: window, manager: self)
        groupWindows[group.id] = controller
        window.makeKeyAndOrderFront(nil)
    }

    fileprivate func handleWindowClosed(_ groupID: UUID) {
        // Remember the size so re-popping reuses it.
        if let window = groupWindows[groupID]?.window,
           let group = floatingGroups.first(where: { $0.id == groupID }),
           let size = window.contentView?.frame.size, !group.panels.isEmpty {
            for panel in group.panels { lastFloatingSize[panel] = size }
        }
        groupWindows[groupID] = nil
        floatingGroups.removeAll { $0.id == groupID }
        rebuildFloatingSet()
        fixActiveBottomTab()
    }
}

/// Retains a pop-out window, keeps its title synced to the group's active
/// panel, and re-docks the group when the window closes.
final class FloatingPanelWindowController: NSObject, NSWindowDelegate {
    let id: UUID
    let window: NSWindow
    weak var manager: PanelManager?
    private var titleCancellable: AnyCancellable?

    @MainActor
    init(group: FloatingGroup, window: NSWindow, manager: PanelManager) {
        self.id = group.id
        self.window = window
        self.manager = manager
        super.init()
        window.delegate = self
        // Title follows the active tab (fires immediately with current value),
        // so merging/splitting/tab-switching keeps the title correct.
        titleCancellable = group.$active.sink { [weak window] active in
            window?.title = active.title
        }
    }

    func windowWillClose(_ notification: Notification) {
        manager?.handleWindowClosed(id)
    }

    func windowDidMove(_ notification: Notification) {
        manager?.noteWindowMoved(id)
    }
}

/// Captures the hosting NSWindow so PanelManager can detect when a floating
/// window is dragged over the main window (to re-dock).
struct MainWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in onResolve(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in onResolve(nsView.window) }
    }
}

/// Live preview shown under the cursor while tearing a panel out — the real
/// panel content at the size the window will be, not just a placeholder.
struct TearLivePreview: View {
    let id: PanelID

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: id.systemImage).font(.caption).foregroundStyle(.secondary)
                Text(id.title).font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(.bar)
            Divider()
            Group {
                switch id {
                case .console:  ConsoleView()
                case .problems: ProblemsView()
                case .fileTree: FileTreeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2))
    }
}
