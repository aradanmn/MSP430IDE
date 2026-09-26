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
        VStack(spacing: Metrics.spacingS) {
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
            registersPane
            breakpointsPane
        }
    }

    private var stoppedView: some View {
        VStack(spacing: 0) {
            registersPane

            // Location header
            if let file = appState.debugCurrentFile, let line = appState.debugCurrentLine {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 11))
                    Text("\(file.lastPathComponent):\(line)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help("\(file.lastPathComponent):\(line)")
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
                        .padding(.horizontal, Metrics.spacingM)
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
        VStack(spacing: Metrics.spacingS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 24))
            Text("Debug Error").font(.headline)
            Text(msg).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// CPU registers, pinned above the location/tab area. Values refresh at
    /// every stop (breakpoint, step, pause); GDB cannot read a remote MSP430's
    /// registers while the core is running, so the grid dims and shows the
    /// last-stop values until the target halts again.
    private var registersPane: some View {
        let isRunning = appState.debugSessionState == .running
        let regs = appState.debugRegisters
        // Adaptive columns: each cell is "R12 0xF800"-sized, so the grid flows
        // to two columns at the panel's minimum width and more when wider.
        let columns = [GridItem(.adaptive(minimum: 96), spacing: Metrics.spacingS, alignment: .leading)]

        return VStack(spacing: 0) {
            HStack {
                Text("Registers")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isRunning {
                    Text(regs.isEmpty ? "target running" : "target running — pause to refresh")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Metrics.spacingS)
            .padding(.vertical, Metrics.spacingXS)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()

            if regs.isEmpty {
                Text(isRunning ? "Pause or hit a breakpoint to read registers"
                               : "No register data")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Metrics.spacingM)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.spacingXS) {
                    ForEach(regs) { reg in
                        HStack(spacing: Metrics.spacingXS) {
                            Text(reg.name)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 26, alignment: .leading)
                            Text(reg.value)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(reg.changed && !isRunning ? Color.orange : Color.primary)
                        }
                        .fixedSize()
                        .help("\(reg.name) = \(reg.value)")
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(reg.name) \(reg.value)")
                    }
                }
                .padding(.horizontal, Metrics.spacingS)
                .padding(.vertical, Metrics.spacingS)
                .opacity(isRunning ? 0.5 : 1)
            }
            Divider()
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
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .help(v.name)
                                    .frame(width: 80, alignment: .leading)
                                Text(v.value)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(v.value)
                                Spacer()
                            }
                            .padding(.horizontal, Metrics.spacingS)
                            .padding(.vertical, Metrics.spacingXS)
                            Divider().padding(.leading, Metrics.spacingS)
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
                                    // Min width keeps single-digit frames aligned; fixedSize
                                    // lets "#100" grow instead of wrapping onto two lines.
                                    Text("#\(frame.id)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .fixedSize()
                                        .frame(minWidth: 24, alignment: .trailing)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(frame.function)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(frame.function)
                                        if let f = frame.file, let l = frame.line {
                                            Text("\(f.lastPathComponent):\(l)")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .help("\(f.lastPathComponent):\(l)")
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
                                BreakpointGlyph(armed: armed, size: Metrics.gutterGlyphSize)
                                    .help(armed ? "Breakpoint" : "Breakpoint (hardware limit — not armed)")
                                Button {
                                    appState.jumpToBreakpoint(file: url, line: line)
                                } label: {
                                    Text("\(url.lastPathComponent):\(line)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help("\(url.lastPathComponent):\(line)")
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
                                .accessibilityLabel("Delete breakpoint at \(url.lastPathComponent) line \(line)")
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
