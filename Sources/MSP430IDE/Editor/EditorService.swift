import Foundation

@MainActor
final class EditorService: ObservableObject {
    @Published var openTabs: [URL] = []
    @Published var activeTab: URL?
    @Published private(set) var recentlyClosed: [URL] = []

    private let recentlyClosedLimit = 20

    func open(_ url: URL) {
        if !openTabs.contains(url) {
            openTabs.append(url)
        }
        activeTab = url
        recentlyClosed.removeAll { $0 == url }
    }

    func close(_ url: URL) {
        guard let idx = openTabs.firstIndex(of: url) else { return }
        openTabs.remove(at: idx)
        recentlyClosed.append(url)
        if recentlyClosed.count > recentlyClosedLimit {
            recentlyClosed.removeFirst(recentlyClosed.count - recentlyClosedLimit)
        }
        if activeTab == url {
            if openTabs.indices.contains(idx) {
                activeTab = openTabs[idx]
            } else {
                activeTab = openTabs.last
            }
        }
    }

    /// Remove a tab without treating it as "closed" (it isn't added to the
    /// recently-closed stack). Used when a file is torn out into its own
    /// editor window — it's still open, just elsewhere.
    func detach(_ url: URL) {
        guard let idx = openTabs.firstIndex(of: url) else { return }
        openTabs.remove(at: idx)
        if activeTab == url {
            if openTabs.indices.contains(idx) {
                activeTab = openTabs[idx]
            } else {
                activeTab = openTabs.last
            }
        }
    }

    func closeAll() {
        recentlyClosed.append(contentsOf: openTabs)
        if recentlyClosed.count > recentlyClosedLimit {
            recentlyClosed.removeFirst(recentlyClosed.count - recentlyClosedLimit)
        }
        openTabs = []
        activeTab = nil
    }

    func select(_ url: URL) {
        guard openTabs.contains(url) else { return }
        activeTab = url
    }

    func selectIndex(_ index: Int) {
        guard openTabs.indices.contains(index) else { return }
        activeTab = openTabs[index]
    }

    func nextTab() {
        guard !openTabs.isEmpty else { return }
        guard let current = activeTab, let i = openTabs.firstIndex(of: current) else {
            activeTab = openTabs.first
            return
        }
        activeTab = openTabs[(i + 1) % openTabs.count]
    }

    func prevTab() {
        guard !openTabs.isEmpty else { return }
        guard let current = activeTab, let i = openTabs.firstIndex(of: current) else {
            activeTab = openTabs.last
            return
        }
        activeTab = openTabs[(i - 1 + openTabs.count) % openTabs.count]
    }

    @discardableResult
    func reopenLastClosed() -> URL? {
        guard let url = recentlyClosed.popLast() else { return nil }
        open(url)
        return url
    }

    func reorder(from source: IndexSet, to destination: Int) {
        openTabs.move(fromOffsets: source, toOffset: destination)
    }

    func restore(workspace: WorkspaceState, project: ProjectModel) {
        let fm = FileManager.default
        let restored: [URL] = workspace.openTabs.compactMap { rel in
            let url = project.rootURL.appendingPathComponent(rel)
            return fm.fileExists(atPath: url.path) ? url : nil
        }
        openTabs = restored
        if let activeRel = workspace.activeTab {
            let url = project.rootURL.appendingPathComponent(activeRel)
            activeTab = openTabs.contains(url) ? url : openTabs.first
        } else {
            activeTab = openTabs.first
        }
    }

    func snapshot(for project: ProjectModel) -> (openTabs: [String], activeTab: String?) {
        let prefix = project.rootURL.path + "/"
        let relativeOpen = openTabs.map { url -> String in
            url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
        }
        let relativeActive = activeTab.map { url -> String in
            url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
        }
        return (relativeOpen, relativeActive)
    }
}
