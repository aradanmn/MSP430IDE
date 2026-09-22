import SwiftUI
import AppKit

/// Diagram/illustration files (see course `diagrams/*.html`) are animated
/// HTML/SVG meant to be viewed in a real browser — the IDE has no rendering
/// engine for them, so opening one launches it externally instead of loading
/// it into an editor tab.
private func opensExternally(_ url: URL) -> Bool {
    ["html", "svg"].contains(url.pathExtension.lowercased())
}

private func openTreeFile(_ url: URL, appState: AppState) {
    if opensExternally(url) {
        NSWorkspace.shared.open(url)
    } else {
        appState.selectFile(url)
    }
}

struct FileTreeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        treeContent
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
                    openTreeFile(url, appState: appState)
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
            Button(opensExternally(url) ? "Open in Browser" : "Open") {
                openTreeFile(url, appState: appState)
            }
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
    /// the app icon's microcontroller motif. Course exercises/quizzes also
    /// get a course-progress badge (top-trailing, so it never collides with
    /// the sub-project chip badge at bottom-trailing).
    @ViewBuilder
    private var icon: some View {
        baseIcon
            .overlay(alignment: .topTrailing) {
                if let badgeIcon = progressBadgeIcon {
                    Image(systemName: badgeIcon)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(1.5)
                        .background(Circle().fill(progressBadgeColor))
                        .offset(x: 3, y: -2)
                }
            }
    }

    @ViewBuilder
    private var baseIcon: some View {
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

    /// The lesson slug (e.g. "lesson-01-architecture") for this node, found
    /// by scanning its root-relative path — `FileNode.id` is already that
    /// relative path string, so no URL reconstruction is needed.
    private var lessonSlugForNode: String? {
        node.id.split(separator: "/").first(where: { $0.hasPrefix("lesson-") }).map(String.init)
    }

    /// Status string ("graded"/"passed"/"in_progress"/…) for this node, if
    /// it's an exercise folder (`ex1`, `ex2`, …) or a `quiz.toml` file with
    /// a matching entry in `appState.courseProgress`.
    private var progressStatus: String? {
        guard let progress = appState.courseProgress,
              let slug = lessonSlugForNode,
              let lesson = progress.lessons[slug] else { return nil }
        if node.isFolder {
            return lesson.exercises[node.name]?.status
        }
        if node.name == "quiz.toml" {
            return lesson.quiz?.status
        }
        return nil
    }

    private var progressBadgeIcon: String? {
        switch progressStatus {
        case "graded", "passed": return "checkmark"
        case "in_progress":      return "ellipsis"
        default:                 return nil
        }
    }

    private var progressBadgeColor: Color {
        progressStatus == "in_progress" ? Color.orange : Color.green
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
        case "html", "svg": return "play.rectangle.fill"
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
        case "html", "svg": return .teal
        default: return .secondary
        }
    }
}
