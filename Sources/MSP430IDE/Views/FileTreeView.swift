import SwiftUI

struct FileTreeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let proj = appState.project {
                let nodes = projectTree(proj)
                List(selection: selectionBinding) {
                    OutlineGroup(nodes, children: \.children) { node in
                        FileTreeRow(node: node).tag(node.id)
                    }

                    Section("Project") {
                        Label(proj.mcu, systemImage: "cpu")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Label(proj.mode.rawValue, systemImage: proj.mode == .native ? "gear.badge" : "hammer")
                            .foregroundStyle(.secondary)
                            .font(.caption)
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
    }

    private func projectTree(_ proj: ProjectModel) -> [FileNode] {
        FileNode.buildTree(
            from: proj.sourceFiles + proj.assemblyFiles + proj.headerFiles,
            root: proj.rootURL
        )
    }

    private var selectionBinding: Binding<String?> {
        Binding<String?>(
            get: { appState.selectedFile.flatMap { url in idFor(url: url) } },
            set: { newID in
                guard let id = newID,
                      let proj = appState.project else { return }
                let nodes = projectTree(proj)
                if let url = lookupURL(in: nodes, id: id) {
                    appState.selectFile(url)
                }
            }
        )
    }

    private func idFor(url: URL) -> String? {
        guard let proj = appState.project else { return nil }
        let rootPrefix = proj.rootURL.path + "/"
        if url.path.hasPrefix(rootPrefix) {
            return String(url.path.dropFirst(rootPrefix.count))
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
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if let url = node.url, appState.buffers[url]?.isDirty == true {
                Spacer()
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
        }
    }

    private var iconName: String {
        if node.isFolder { return "folder" }
        switch node.url?.pathExtension.lowercased() {
        case "c": return "c.square"
        case "h": return "h.square"
        case "s", "asm": return "s.square"
        case "toml": return "doc.text"
        case "json": return "curlybraces"
        case "md": return "doc.richtext"
        default: return "doc"
        }
    }

    private var iconColor: Color {
        if node.isFolder { return .accentColor }
        switch node.url?.pathExtension.lowercased() {
        case "c": return .blue
        case "h": return .purple
        case "s", "asm": return .orange
        case "toml", "json": return .secondary
        default: return .secondary
        }
    }
}
