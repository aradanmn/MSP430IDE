import SwiftUI

struct DebuggerView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        switch appState.debugSessionState {
        case .idle:
            idlePlaceholder
        case .starting:
            startingView
        case .running:
            runningView
        case .stopped:
            stoppedView
        case .error(let msg):
            errorView(msg)
        }
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "ant.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Not Debugging")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Build with debug symbols, then click Debug.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var startingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Starting debug session…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var runningView: some View {
        VStack(spacing: 0) {
            breakpointsPane
        }
    }

    private var stoppedView: some View {
        VStack(spacing: 0) {
            // Location header
            if let file = appState.debugCurrentFile, let line = appState.debugCurrentLine {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 11))
                    Text("\(file.lastPathComponent):\(line)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()
            }

            // Tab bar
            HStack(spacing: 0) {
                ForEach(["Variables", "Stack", "Breakpoints"].enumerated().map { $0 }, id: \.offset) { idx, title in
                    Button(title) { selectedTab = idx }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selectedTab == idx ? Color(nsColor: .selectedControlColor).opacity(0.5) : Color.clear)
                        .contentShape(Rectangle())
                }
                Spacer()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()

            switch selectedTab {
            case 0: variablesPane
            case 1: stackPane
            default: breakpointsPane
            }
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 24))
            Text("Debug Error").font(.headline)
            Text(msg).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var variablesPane: some View {
        Group {
            if appState.debugLocals.isEmpty {
                Text("No locals").foregroundStyle(.secondary).font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appState.debugLocals) { v in
                            HStack(alignment: .top, spacing: 8) {
                                Text(v.name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .frame(width: 80, alignment: .leading)
                                Text(v.value)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            Divider().padding(.leading, 8)
                        }
                    }
                }
            }
        }
    }

    private var stackPane: some View {
        Group {
            if appState.debugStack.isEmpty {
                Text("No stack frames").foregroundStyle(.secondary).font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appState.debugStack) { frame in
                            Button {
                                appState.selectDebugFrame(frame)
                            } label: {
                                HStack(spacing: 6) {
                                    Text("#\(frame.id)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 24, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(frame.function)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.primary)
                                        if let f = frame.file, let l = frame.line {
                                            Text("\(f.lastPathComponent):\(l)")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(frame.id == appState.debugStack.first?.id
                                        ? Color(nsColor: .selectedControlColor).opacity(0.2)
                                        : Color.clear)
                            Divider().padding(.leading, 8)
                        }
                    }
                }
            }
        }
    }

    private var breakpointsPane: some View {
        let allBkpts = appState.breakpoints.flatMap { url, lines in
            lines.sorted().map { (url, $0) }
        }.sorted { a, b in a.0.lastPathComponent < b.0.lastPathComponent || (a.0 == b.0 && a.1 < b.1) }
        let limit = appState.project?.hardwareBreakpointLimit ?? 2
        let count = appState.breakpointCount

        return VStack(spacing: 0) {
            // Breakpoint count / limit header
            HStack {
                Text("\(count) of \(limit) hardware breakpoints used")
                    .font(.system(size: 10))
                    .foregroundStyle(count >= limit ? Color.orange : Color.secondary)
                Spacer()
                if let mcu = appState.project?.mcu {
                    Text(mcu)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()

            if allBkpts.isEmpty {
                Text("Click in the gutter to set a breakpoint")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(allBkpts, id: \.1) { url, line in
                            HStack(spacing: 6) {
                                Image(systemName: "octagon.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.red)
                                Button {
                                    appState.jumpToBreakpoint(file: url, line: line)
                                } label: {
                                    Text("\(url.lastPathComponent):\(line)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button {
                                    appState.toggleBreakpoint(file: url, line: line)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            Divider().padding(.leading, 8)
                        }
                    }
                }
            }
        }
    }
}
