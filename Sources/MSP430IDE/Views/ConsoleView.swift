import SwiftUI

struct ConsoleView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(.secondary)
                Text("Console")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    appState.clearConsole()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear console")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

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
}
