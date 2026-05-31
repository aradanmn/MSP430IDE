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
}

/// Ghost shown under the cursor while tearing an editor tab into a window.
struct EditorTearCard: View {
    let filename: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(filename)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6])))
        .padding(6)
    }
}
