import SwiftUI

struct AppToolbar: ToolbarContent {
    @EnvironmentObject var appState: AppState

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            // Only native projects have selectable build configs. External
            // projects defer everything to the Makefile, so there's nothing
            // to pick — hide the control entirely.
            if let proj = appState.project, proj.mode == .native {
                Menu {
                    ForEach(proj.configNames, id: \.self) { name in
                        Button {
                            appState.setActiveConfig(name)
                        } label: {
                            HStack {
                                Text(name)
                                if name == appState.activeConfig {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text(appState.activeConfig)
                    }
                }
                .help("Active build configuration")
                .fixedSize()
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await appState.build() }
            } label: {
                Label("Build", systemImage: "hammer.fill")
            }
            .disabled(appState.project == nil || appState.isBuilding)
            .help("Compile (⌘B)")

            Button {
                Task { await appState.flash() }
            } label: {
                Label("Flash", systemImage: "bolt.fill")
            }
            .disabled(appState.project == nil || appState.isFlashing)
            .help("Flash to device (⌘R)")

            // Debug controls
            if appState.isDebugging {
                Button {
                    Task { await appState.stopDebugging() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .foregroundStyle(.red)
                .help("Stop debugging (⌘⇧D)")

                if appState.debugSessionState == .stopped {
                    Button { appState.debugContinue() } label: {
                        Label("Continue", systemImage: "play.fill")
                    }
                    .help("Continue (F5)")
                    Button { appState.debugStepOver() } label: {
                        Label("Step Over", systemImage: "arrow.right.to.line")
                    }
                    .help("Step Over (F6)")
                    Button { appState.debugStepIn() } label: {
                        Label("Step In", systemImage: "arrow.turn.down.right")
                    }
                    .help("Step In (F7)")
                    Button { appState.debugStepOut() } label: {
                        Label("Step Out", systemImage: "arrow.turn.up.right")
                    }
                    .help("Step Out (F8)")
                } else if appState.debugSessionState == .running {
                    Button { appState.debugPause() } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .help("Pause")
                }
            } else {
                Button {
                    Task { await appState.startDebugging() }
                } label: {
                    Label("Debug", systemImage: "ant.fill")
                }
                .disabled(appState.project == nil || appState.isBuilding || appState.isFlashing)
                .help("Start debugger (⌘D)")
            }
        }
    }
}
