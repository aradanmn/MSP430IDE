import SwiftUI

struct FileTreeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List(selection: Binding(
            get: { appState.selectedFile },
            set: { if let url = $0 { appState.selectFile(url) } }
        )) {
            if let proj = appState.project {
                if !proj.sourceFiles.isEmpty {
                    Section("C Sources") {
                        ForEach(proj.sourceFiles, id: \.self) { url in
                            FileRow(url: url).tag(url)
                        }
                    }
                }
                if !proj.assemblyFiles.isEmpty {
                    Section("Assembly") {
                        ForEach(proj.assemblyFiles, id: \.self) { url in
                            FileRow(url: url).tag(url)
                        }
                    }
                }
                if !proj.headerFiles.isEmpty {
                    Section("Headers") {
                        ForEach(proj.headerFiles, id: \.self) { url in
                            FileRow(url: url).tag(url)
                        }
                    }
                }
                Section("Project") {
                    Label(proj.mcu, systemImage: "cpu")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Label(proj.mode.rawValue, systemImage: proj.mode == .native ? "gear.badge" : "hammer")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else {
                Text("No project open")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .listStyle(.sidebar)
    }
}

struct FileRow: View {
    let url: URL
    @EnvironmentObject var appState: AppState

    var body: some View {
        let isDirty = appState.buffers[url]?.isDirty ?? false
        let suffix = appState.project?.disambiguators[url] ?? ""
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(url.lastPathComponent)
            if !suffix.isEmpty {
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(url.path)
            }
            if isDirty {
                Spacer()
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
        }
    }

    private var iconName: String {
        switch url.pathExtension.lowercased() {
        case "c": return "c.square"
        case "h": return "h.square"
        case "s", "asm": return "s.square"
        default: return "doc"
        }
    }

    private var iconColor: Color {
        switch url.pathExtension.lowercased() {
        case "c": return .blue
        case "h": return .purple
        case "s", "asm": return .orange
        default: return .secondary
        }
    }
}
