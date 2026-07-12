import SwiftUI

struct DebuggerView: View {
    @EnvironmentObject var appState: AppState

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
                ForEach(["Registers", "Variables", "Stack", "Breakpoints"].enumerated().map { $0 }, id: \.offset) { idx, title in
                    Button(title) { appState.debugPanelTab = idx }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(appState.debugPanelTab == idx ? Color(nsColor: .selectedControlColor).opacity(0.5) : Color.clear)
                        .contentShape(Rectangle())
                }
                Spacer()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()

            switch appState.debugPanelTab {
            case 0: registersPane
            case 1: variablesPane
            case 2: stackPane
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

    private var registersPane: some View {
        Group {
            if appState.debugRegisters.isEmpty {
                Text("No registers").foregroundStyle(.secondary).font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appState.debugRegisters) { reg in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 0) {
                                    Text(reg.displayName)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .frame(width: 64, alignment: .leading)
                                    Text(reg.hexString)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                // SR flags inline under the SR row
                                if let flags = reg.srFlags {
                                    HStack(spacing: 4) {
                                        ForEach(flags, id: \.name) { flag in
                                            Text(flag.name)
                                                .font(.system(size: 9, weight: flag.set ? .bold : .regular, design: .monospaced))
                                                .foregroundStyle(flag.set ? Color.primary : Color(nsColor: .tertiaryLabelColor))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(flag.set ? Color(nsColor: .selectedControlColor).opacity(0.5) : Color.clear)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                        Spacer()
                                    }
                                    .padding(.leading, 72)
                                    .padding(.bottom, 3)
                                }
                            }
                            Divider().padding(.leading, 8)
                        }
                    }
                }
            }
        }
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
        let allBkpts: [(URL, Int)] = appState.breakpoints
            .flatMap { url, lines in lines.sorted().map { (url, $0) } }
            .sorted { lhs, rhs in
                if lhs.0.lastPathComponent != rhs.0.lastPathComponent {
                    return lhs.0.lastPathComponent < rhs.0.lastPathComponent
                }
                return lhs.1 < rhs.1
            }
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
                            let armed = appState.isBreakpointConfirmed(file: url, line: line)
                            HStack(spacing: 6) {
                                BreakpointGlyph(armed: armed, size: 9)
                                    .help(armed ? "Breakpoint" : "Breakpoint (hardware limit — not armed)")
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
