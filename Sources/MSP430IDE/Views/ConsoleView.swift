import SwiftUI

/// Raw build/flash output, scrolled. Diagnostics moved to ProblemsView
/// (the sibling tab). The TabStrip header lives in `BottomPanel`, so
/// this view is just the scrolling text area.
struct ConsoleView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(appState.consoleOutput.isEmpty ? " " : appState.consoleOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                Color.clear.frame(height: 1).id("bottom")
            }
            .onChange(of: appState.consoleOutput) { _ in
                withAnimation(.none) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
