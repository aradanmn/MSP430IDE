import SwiftUI
import AppKit

struct FileTreeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var panels: PanelManager
    /// Show the pop-out control (only in the docked sidebar, not when this
    /// view is already inside a floating window).
    var showPopOutControl: Bool = false
    @State private var torn = false

    var body: some View {
        VStack(spacing: 0) {
            if showPopOutControl, !panels.isFloating(.fileTree) {
                header
            }
            treeContent
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(appState.workspaceRoot?.lastPathComponent ?? "Files")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button {
                panels.popOut(.fileTree)
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.borderless)
            .help("Open the file tree in a new window")
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        // Drag the header to tear the tree out into a window (like a tab).
        .simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .global)
                .onChanged { value in
                    if !torn && (value.translation.width > 24 || abs(value.translation.height) > 60) {
                        torn = true
                        panels.beginTearPreview(.fileTree)
                    }
                    if torn { panels.moveTearPreview(to: NSEvent.mouseLocation) }
                }
                .onEnded { _ in
                    if torn {
                        panels.endTear(commit: true, id: .fileTree, at: NSEvent.mouseLocation)
                        torn = false
                    }
                }
        )
    }

    @ViewBuilder
    private var treeContent: some View {
        if let root = appState.workspaceRoot {
            let nodes = FileNode.buildTree(from: appState.displayFiles, root: root)
            List(selection: selectionBinding) {
                OutlineGroup(nodes, children: \.children) { node in
                    FileTreeRow(node: node).tag(node.id)
                }
            }
            .listStyle(.sidebar)
        } else {
            Text("No project open")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding<String?>(
            get: { appState.selectedFile.flatMap { url in idFor(url: url) } },
            set: { newID in
                guard let id = newID, let root = appState.workspaceRoot else { return }
                let nodes = FileNode.buildTree(from: appState.displayFiles, root: root)
                if let url = lookupURL(in: nodes, id: id) {
                    appState.selectFile(url)
                }
            }
        )
    }

    private func idFor(url: URL) -> String? {
        guard let root = appState.workspaceRoot else { return nil }
        let prefix = root.path + "/"
        if url.path.hasPrefix(prefix) {
            return String(url.path.dropFirst(prefix.count))
        }
        return url.lastPathComponent
    }

    private func lookupURL(in nodes: [FileNode], id: String) -> URL? {
        for node in nodes {
            if node.id == id, let url = node.url { return url }
            if let kids = node.children, let found = lookupURL(in: kids, id: id) {
                return found
            }
        }
        return nil
    }
}

private struct FileTreeRow: View {
    let node: FileNode
    @EnvironmentObject var appState: AppState

    var body: some View {
        let isSubproject = isProjectFolder
        HStack(spacing: 6) {
            icon
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .fontWeight(isSubproject ? .semibold : .regular)
            if let url = node.url, appState.buffers[url]?.isDirty == true {
                Spacer()
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
        }
        .contextMenu { contextMenuItems }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if node.isFolder, let folderURL = folderURL {
            if isProjectFolder {
                Text("Sub-project: \(node.name)")
                    .foregroundStyle(.secondary)
            } else {
                Button("Create Project Config Here") {
                    appState.createProjectConfig(at: folderURL)
                }
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([folderURL])
            }
        } else if let url = node.url {
            Button("Open") { appState.selectFile(url) }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private var folderURL: URL? {
        guard node.isFolder, let root = appState.workspaceRoot else { return nil }
        return root.appendingPathComponent(node.id)
    }

    private var isProjectFolder: Bool {
        guard let folderURL = folderURL else { return false }
        return appState.subprojects[folderURL] != nil
    }

    /// Row icon. Sub-projects get a folder with a small hammer badge
    /// (composed, since SF Symbols has no `folder.badge.hammer`).
    /// Row icon. Sub-projects get a folder with a small chip badge
    /// (composed, since SF Symbols has no `folder.badge.cpu`) — echoing
    /// the app icon's microcontroller motif.
    @ViewBuilder
    private var icon: some View {
        if isProjectFolder {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.teal)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(Circle().fill(Color.indigo))
                        .offset(x: 3, y: 2)
                }
        } else {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        if node.isFolder { return "folder" }
        switch node.url?.pathExtension.lowercased() {
        case "c": return "c.square"
        case "h": return "h.square"
        case "s", "asm": return "s.square"
        case "md", "markdown", "mdown": return "doc.richtext"
        case "txt", "text": return "doc.plaintext"
        case "toml": return "doc.badge.gearshape"
        case "json": return "curlybraces"
        case "ld": return "memorychip"
        default: return "doc"
        }
    }

    private var iconColor: Color {
        if node.isFolder { return .secondary }
        switch node.url?.pathExtension.lowercased() {
        case "c": return .blue
        case "h": return .purple
        case "s", "asm": return .orange
        case "md", "markdown", "mdown": return .green
        case "toml": return .brown
        case "json": return .yellow
        case "ld": return .pink
        default: return .secondary
        }
    }
}
