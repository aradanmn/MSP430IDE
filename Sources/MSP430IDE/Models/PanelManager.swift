import SwiftUI
import AppKit
import Combine

/// Identifier for every dockable / detachable panel in the IDE.
enum PanelID: String, CaseIterable, Identifiable, Hashable, Codable {
    case console
    case problems
    case fileTree
    case debugger

    var id: String { rawValue }

    var title: String {
        switch self {
        case .console:   return "Console"
        case .problems:  return "Issues"
        case .fileTree:  return "Files"
        case .debugger:  return "Debugger"
        }
    }

    var systemImage: String {
        switch self {
        case .console:  return "terminal.fill"
        case .problems: return "exclamationmark.triangle.fill"
        case .fileTree: return "folder.fill"
        case .debugger: return "ant.fill"
        }
    }
}

/// A dock region around the central editor.
enum DockEdge: String, CaseIterable, Hashable {
    case left, right, top, bottom
}

/// One floating window's worth of panels, shown as tabs.
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

/// Owns the dock layout (which panels live at which edge), and every floating
/// window. Panels are either docked at an edge or floating in a window; they
/// can be dragged between any edge, into floating windows, or merged together.
@MainActor
final class PanelManager: ObservableObject {
    /// Edge each panel docks to when not floating.
    @Published var dockEdge: [PanelID: DockEdge] = [
        .fileTree: .left, .console: .bottom, .problems: .bottom, .debugger: .right
    ]
    /// Active (selected) panel within each edge region.
    @Published var activePerEdge: [DockEdge: PanelID] = [.left: .fileTree, .bottom: .console]

    @Published var floatingGroups: [FloatingGroup] = []
    @Published private(set) var floatingPanels: Set<PanelID> = []

    /// Panels that are configured but not currently shown (e.g. the debugger
    /// before a session starts). Revealed on demand.
    @Published private(set) var hiddenPanels: Set<PanelID> = [.debugger]

    weak var appState: AppState?
    weak var mainWindow: NSWindow?

    private var groupWindows: [UUID: FloatingPanelWindowController] = [:]
    private var tearPreviewWindow: NSWindow?
    private var lastFloatingSize: [PanelID: NSSize] = [:]

    private var draggedGroupID: UUID?
    private var suppressMoveTracking = false
    private var mouseUpMonitors: [Any] = []

    func attach(appState: AppState) {
        self.appState = appState
        installDragMonitorsIfNeeded()
    }

    func setMainWindow(_ window: NSWindow?) { mainWindow = window }

    private func defaultSize(_ id: PanelID) -> NSSize {
        id == .fileTree ? NSSize(width: 280, height: 480) : NSSize(width: 640, height: 320)
    }

    // MARK: - Dock queries

    func isFloating(_ id: PanelID) -> Bool { floatingPanels.contains(id) }

    /// Panels currently docked at `edge`, in a stable order.
    func dockedPanels(at edge: DockEdge) -> [PanelID] {
        PanelID.allCases.filter {
            !floatingPanels.contains($0) && !hiddenPanels.contains($0) && (dockEdge[$0] ?? .bottom) == edge
        }
    }

    /// Show a previously hidden panel (e.g. the debugger when a session starts).
    func reveal(_ id: PanelID) {
        hiddenPanels.remove(id)
        showPanel(id)
    }

    /// Hide a panel from the dock without changing its remembered edge.
    func hide(_ id: PanelID) {
        hiddenPanels.insert(id)
    }

    func hasPanels(at edge: DockEdge) -> Bool { !dockedPanels(at: edge).isEmpty }

    func activePanel(at edge: DockEdge) -> PanelID? {
        let docked = dockedPanels(at: edge)
        if let active = activePerEdge[edge], docked.contains(active) { return active }
        return docked.first
    }

    func isActive(_ id: PanelID, at edge: DockEdge) -> Bool { activePanel(at: edge) == id }

    func selectDocked(_ id: PanelID) {
        guard let edge = dockEdge[id], !floatingPanels.contains(id) else { return }
        activePerEdge[edge] = id
    }

    /// Bring a panel to the foreground wherever it lives.
    func showPanel(_ id: PanelID) {
        if let group = floatingGroups.first(where: { $0.panels.contains(id) }) {
            group.active = id
            groupWindows[group.id]?.window.makeKeyAndOrderFront(nil)
            return
        }
        selectDocked(id)
    }

    /// Dock a panel (currently floating or at another edge) to `edge`.
    func dock(_ id: PanelID, to edge: DockEdge) {
        removeFromCurrentGroup(id)
        dockEdge[id] = edge
        activePerEdge[edge] = id
        rebuildFloatingSet()
    }

    // MARK: - Pop-out via button / programmatic

    func popOut(_ id: PanelID) { moveToNewGroup(id, at: nil) }

    func togglePopOut(_ id: PanelID) {
        if isFloating(id) { dockBack(id) } else { popOut(id) }
    }

    /// Dock a single panel back to its current edge (removing it from float).
    func dockBack(_ id: PanelID) {
        let edge = dockEdge[id] ?? .bottom
        dock(id, to: edge)
    }

    /// Dock an entire floating group back (its window closed).
    func dockGroup(_ groupID: UUID) { groupWindows[groupID]?.window.close() }

    // MARK: - Drag-to-dock (grab a floating window by its title bar)

    private func installDragMonitorsIfNeeded() {
        guard mouseUpMonitors.isEmpty else { return }
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
        updateDockHighlight(forGroup: groupID)
    }

    private func handleWindowDragRelease() {
        hideDockHighlight()
        guard let movedID = draggedGroupID else { return }
        draggedGroupID = nil
        let point = NSEvent.mouseLocation

        // Over another floating window → merge.
        if let targetID = groupWindows.first(where: { $0.key != movedID && $0.value.window.frame.contains(point) })?.key {
            mergeGroup(movedID, into: targetID)
            return
        }
        // Over the main window → dock all the group's panels to the nearest edge.
        if let mw = mainWindow, mw.frame.contains(point),
           let group = floatingGroups.first(where: { $0.id == movedID }) {
            let edge = nearestEdge(to: point, in: mw.frame)
            let panels = group.panels
            for panel in panels { dockEdge[panel] = edge }
            activePerEdge[edge] = panels.last
            group.panels.removeAll()        // empties the group → window closes
            groupWindows[movedID]?.window.close()
            rebuildFloatingSet()
        }
    }

    private func nearestEdge(to point: NSPoint, in frame: NSRect) -> DockEdge {
        let fx = (point.x - frame.minX) / max(frame.width, 1)   // 0 = left … 1 = right
        let fy = (point.y - frame.minY) / max(frame.height, 1)  // 0 = bottom … 1 = top
        let distances: [(DockEdge, CGFloat)] = [
            (.left, fx), (.right, 1 - fx), (.bottom, fy), (.top, 1 - fy)
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? .bottom
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
        groupWindows[sourceID]?.window.close()
        rebuildFloatingSet()
        groupWindows[targetID]?.window.makeKeyAndOrderFront(nil)
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
        tearPreviewWindow?.setFrameTopLeftPoint(NSPoint(x: screenPoint.x - 40, y: screenPoint.y + 14))
        // Show where it would dock if released over the main window.
        if let mw = mainWindow, mw.frame.contains(screenPoint) {
            showDockHighlight(rect(for: nearestEdge(to: screenPoint, in: mw.frame), in: mw.frame))
        } else {
            hideDockHighlight()
        }
    }

    /// Finish tearing a tab. Over a floating window → merge; over the main
    /// window → dock to the nearest edge; elsewhere → float in a new window.
    func endTear(commit: Bool, id: PanelID, at screenPoint: NSPoint) {
        tearPreviewWindow?.orderOut(nil)
        tearPreviewWindow = nil
        hideDockHighlight()
        guard commit else { return }

        if let targetID = groupWindows.first(where: { $0.value.window.frame.contains(screenPoint) })?.key,
           let target = floatingGroups.first(where: { $0.id == targetID }) {
            merge(id, into: target)
        } else if let mw = mainWindow, mw.frame.contains(screenPoint) {
            dock(id, to: nearestEdge(to: screenPoint, in: mw.frame))
        } else {
            moveToNewGroup(id, at: screenPoint)
        }
    }

    // MARK: - Group mutations

    private func currentGroup(of id: PanelID) -> FloatingGroup? {
        floatingGroups.first { $0.panels.contains(id) }
    }

    private func merge(_ id: PanelID, into target: FloatingGroup) {
        if currentGroup(of: id) === target { target.active = id; return }
        target.panels.append(id)
        target.active = id
        removeFromCurrentGroup(id, except: target)
        rebuildFloatingSet()
        groupWindows[target.id]?.window.makeKeyAndOrderFront(nil)
    }

    private func moveToNewGroup(_ id: PanelID, at screenPoint: NSPoint?) {
        if let g = currentGroup(of: id), g.panels == [id] {
            if let p = screenPoint {
                suppressMoveTracking = true
                groupWindows[g.id]?.window.setFrameTopLeftPoint(NSPoint(x: p.x - 40, y: p.y + 14))
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

    private func removeFromCurrentGroup(_ id: PanelID, except keep: FloatingGroup? = nil) {
        for group in floatingGroups where group !== keep && group.panels.contains(id) {
            group.panels.removeAll { $0 == id }
            if group.panels.isEmpty {
                groupWindows[group.id]?.window.close()
            } else if group.active == id {
                group.active = group.panels.first!
            }
        }
    }

    private func rebuildFloatingSet() {
        floatingPanels = Set(floatingGroups.flatMap { $0.panels })
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
            window.setFrameTopLeftPoint(NSPoint(x: p.x - 40, y: p.y + 14))
        } else {
            window.center()
        }
        suppressMoveTracking = false
        let controller = FloatingPanelWindowController(group: group, window: window, manager: self)
        groupWindows[group.id] = controller
        window.makeKeyAndOrderFront(nil)
    }

    fileprivate func handleWindowClosed(_ groupID: UUID) {
        if let window = groupWindows[groupID]?.window,
           let group = floatingGroups.first(where: { $0.id == groupID }),
           let size = window.contentView?.frame.size, !group.panels.isEmpty {
            for panel in group.panels { lastFloatingSize[panel] = size }
        }
        groupWindows[groupID] = nil
        floatingGroups.removeAll { $0.id == groupID }
        rebuildFloatingSet()
    }

    // MARK: - Dock-zone highlight

    private var dockHighlight: NSWindow?

    private func updateDockHighlight(forGroup groupID: UUID) {
        guard let mw = mainWindow, mw.frame.contains(NSEvent.mouseLocation) else {
            hideDockHighlight(); return
        }
        showDockHighlight(rect(for: nearestEdge(to: NSEvent.mouseLocation, in: mw.frame), in: mw.frame))
    }

    private func rect(for edge: DockEdge, in frame: NSRect) -> NSRect {
        switch edge {
        case .left:   return NSRect(x: frame.minX, y: frame.minY, width: frame.width * 0.28, height: frame.height)
        case .right:  return NSRect(x: frame.maxX - frame.width * 0.28, y: frame.minY, width: frame.width * 0.28, height: frame.height)
        case .bottom: return NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height * 0.3)
        case .top:    return NSRect(x: frame.minX, y: frame.maxY - frame.height * 0.3, width: frame.width, height: frame.height * 0.3)
        }
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

    private func hideDockHighlight() { dockHighlight?.orderOut(nil) }
}

/// Retains a pop-out window, keeps its title synced to the active tab, and
/// re-docks the group when the window closes.
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
        titleCancellable = group.$active.sink { [weak window] active in
            window?.title = active.title
        }
    }

    func windowWillClose(_ notification: Notification) { manager?.handleWindowClosed(id) }
    func windowDidMove(_ notification: Notification) { manager?.noteWindowMoved(id) }
}

/// Captures the hosting NSWindow so PanelManager can detect drags over it.
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

/// Live preview shown under the cursor while tearing a panel out.
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
                PanelContentView(id: id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2))
    }
}
