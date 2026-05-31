import SwiftUI
import AppKit

struct TabBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(appState.editor.openTabs, id: \.self) { url in
                    TabItem(url: url)
                }
            }
        }
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct TabItem: View {
    let url: URL
    @EnvironmentObject var appState: AppState
    @State private var hovering = false
    @State private var torn = false

    var body: some View {
        let isActive = appState.editor.activeTab == url
        let isDirty = appState.buffers[url]?.isDirty ?? false

        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(iconColor)

            Text(url.lastPathComponent)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isActive ? .primary : .secondary)

            if isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            } else if hovering {
                Button {
                    appState.closeTab(url)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.borderless)
                .help("Close (⌘W)")
            } else {
                Color.clear.frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxHeight: .infinity)
        .background {
            if isActive {
                Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
            } else if hovering {
                Color(nsColor: .windowBackgroundColor).opacity(0.5)
            }
        }
        .overlay(alignment: .trailing) {
            Divider()
        }
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.editor.select(url)
            appState.selectFile(url)
        }
        .onHover { hovering = $0 }
        // Tear the tab out into its own editor window (live preview, placed
        // on release). Plain clicks still select.
        .simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .global)
                .onChanged { value in
                    if !torn && (value.translation.height > 22 || abs(value.translation.width) > 90) {
                        torn = true
                        appState.beginEditorTearPreview(url)
                    }
                    if torn { appState.moveEditorTearPreview(to: NSEvent.mouseLocation) }
                }
                .onEnded { _ in
                    if torn {
                        appState.endEditorTear(commit: true, url: url, at: NSEvent.mouseLocation)
                        torn = false
                    }
                }
        )
        .contextMenu {
            Button("Open in New Window") { appState.popOutEditor(url) }
            Divider()
            Button("Close") { appState.closeTab(url) }
            Button("Close Others") {
                for other in appState.editor.openTabs where other != url {
                    appState.closeTab(other)
                }
            }
            Button("Close All") { appState.closeAllTabs() }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
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
