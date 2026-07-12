import SwiftUI

/// The entire menu bar. Deliberately observes only MenuState (see that type
/// for why observing AppState from .commands breaks open menus); appState
/// and panels are captured for actions only, which creates no dependency.
struct AppCommands: Commands {
    let appState: AppState
    let panels: PanelManager
    @ObservedObject var menu: MenuState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                appState.createProject()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open Project Folder…") {
                appState.promptOpenProject()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Close File") {
                if let url = appState.selectedFile { appState.closeTab(url) }
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(!menu.hasSelectedFile)

            Button("Close Project") {
                appState.closeProject()
            }
            .disabled(!menu.hasWorkspace)

            Button("Create Project Config Here…") {
                appState.createProjectConfigHere()
            }
            .disabled(!menu.hasWorkspace)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { appState.saveCurrent() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!menu.hasSelectedFile)

            Button("Save All") { appState.saveAll() }
                .keyboardShortcut("s", modifiers: [.command, .option])
        }

        CommandMenu("Tabs") {
            Button("Close All Tabs") { appState.closeAllTabs() }
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(menu.openTabCount == 0)

            Button("Reopen Last Closed") { appState.reopenLastClosed() }
                .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Next Tab") { appState.nextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(menu.openTabCount < 2)

            Button("Previous Tab") { appState.prevTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(menu.openTabCount < 2)

            Divider()

            ForEach(0..<9, id: \.self) { i in
                Button("Go to Tab \(i + 1)") { appState.selectTabAt(i) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .disabled(menu.openTabCount <= i)
            }
        }

        CommandMenu("Build") {
            Button("Build") {
                Task { await appState.build() }
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(!menu.hasProject || menu.isBuilding)

            Button("Flash") {
                Task { await appState.flash() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!menu.hasProject || menu.isFlashing)

            Divider()

            Button("Clean Build Folder") {
                appState.cleanBuild()
            }

            Divider()

            Menu("Build Mode") {
                Button {
                    appState.setBuildMode(.native)
                } label: {
                    Label("Native (compile directly)",
                          systemImage: menu.buildMode == .native ? "checkmark" : "")
                }
                Button {
                    appState.setBuildMode(.external)
                } label: {
                    Label("External (use Makefile)",
                          systemImage: menu.buildMode == .external ? "checkmark" : "")
                }
            }
            .disabled(!menu.hasProject)
        }

        CommandMenu("Debug") {
            Button("Start Debugging") {
                Task { await appState.startDebugging() }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!menu.hasProject || menu.isDebugging)

            Button("Stop Debugging") {
                Task { await appState.stopDebugging() }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(!menu.isDebugging)

            Divider()

            Button("Continue") {
                appState.debugContinue()
            }
            .disabled(!menu.debugStopped)

            Button("Step Over") {
                appState.debugStepOver()
            }
            .disabled(!menu.debugStopped)

            Button("Step In") {
                appState.debugStepIn()
            }
            .disabled(!menu.debugStopped)

            Button("Step Out") {
                appState.debugStepOut()
            }
            .disabled(!menu.debugStopped)

            Divider()

            Button("Show Debugger Panel") {
                panels.showPanel(.debugger)
            }
        }
    }
}
