import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                FileTreeView()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 360)
            } detail: {
                VSplitView {
                    EditorPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ConsoleView()
                        .frame(minHeight: 100, idealHeight: 180)
                }
                .frame(minWidth: 400)
            }
            .navigationTitle(appState.project?.rootURL.lastPathComponent ?? "MSP430 IDE")
            .toolbar { AppToolbar() }

            StatusBar()
        }
    }
}

struct EditorPane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if !appState.editor.openTabs.isEmpty {
                TabBar()
            }
            if let url = appState.selectedFile, let buffer = appState.buffers[url] {
                EditorPaneContent(url: url, buffer: buffer)
                    .id(url)
            } else {
                WelcomeView()
            }
        }
    }
}

private struct EditorPaneContent: View {
    let url: URL
    @ObservedObject var buffer: TextBuffer
    @State private var gutter = GutterState()

    var body: some View {
        VStack(spacing: 0) {
            FileHeader(url: url, buffer: buffer)
            HStack(spacing: 0) {
                GutterView(state: gutter)
                CodeEditorView(buffer: buffer, gutter: gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FileHeader: View {
    let url: URL
    @ObservedObject var buffer: TextBuffer

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.system(.body, design: .monospaced))
            if buffer.isDirty {
                Text("•").foregroundStyle(.orange).bold()
            }
            Spacer()
            Text("\(buffer.text.count) chars")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("MSP430 IDE")
                .font(.system(size: 32, weight: .light))
            Text("A native macOS environment for MSP430 microcontrollers")
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Button { appState.promptOpenProject() } label: {
                        Label("Open Project Folder…", systemImage: "folder")
                            .frame(minWidth: 180)
                    }
                    .controlSize(.large)

                    Button { appState.createBlinkProject() } label: {
                        Label("New Blink Project…", systemImage: "sparkles")
                            .frame(minWidth: 180)
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
                VStack(spacing: 10) {
                    Button { appState.promptOpenProject() } label: {
                        Label("Open Project Folder…", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)

                    Button { appState.createBlinkProject() } label: {
                        Label("New Blink Project…", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: 320)
            }
            .padding(.top, 8)

            ToolchainStatusView()
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct ToolchainStatusView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("Toolchain")
                    .font(.headline)
                row("msp430-elf-gcc", appState.toolchain.gccPath?.path)
                row("mspdebug", appState.toolchain.mspdebugPath?.path)
                row("device headers", appState.toolchain.supportIncludePath?.path, optional: true)

                if !appState.toolchain.isReady {
                    Text("Install missing tools, then relaunch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(8)
        }
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    func row(_ label: String, _ path: String?, optional: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: path != nil ? "checkmark.circle.fill" : (optional ? "questionmark.circle" : "xmark.circle.fill"))
                .foregroundStyle(path != nil ? Color.green : (optional ? Color.orange : Color.red))
            Text(label)
                .frame(width: 130, alignment: .leading)
                .bold()
            Text(path ?? "not found")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
