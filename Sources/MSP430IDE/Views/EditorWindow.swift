import SwiftUI
import AppKit

/// Retains a popped-out editor window and re-docks the file when it closes.
final class EditorWindowController: NSObject, NSWindowDelegate {
    let url: URL
    let window: NSWindow
    weak var appState: AppState?

    init(url: URL, window: NSWindow, appState: AppState) {
        self.url = url
        self.window = window
        self.appState = appState
        super.init()
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        // NSWindowDelegate is MainActor-isolated, so this is safe.
        appState?.editorWindowClosed(url)
    }

    func windowDidMove(_ notification: Notification) {
        appState?.noteEditorWindowMoved(url)
    }
}

/// Live preview shown under the cursor while tearing an editor tab into a
/// window — a read-only rendering of the file content at the window's size.
struct EditorTearPreview: View {
    let filename: String
    @ObservedObject var buffer: TextBuffer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.caption).foregroundStyle(.secondary)
                Text(filename).font(.system(.caption, design: .monospaced))
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(.bar)
            Divider()
            ScrollView {
                Text(String(buffer.text.prefix(6000)))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .disabled(true)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2))
    }
}
