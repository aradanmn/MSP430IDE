import SwiftUI
import AppKit

@main
struct MSP430IDEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    init() {
        if let path = ProcessInfo.processInfo.environment["MSP430IDE_VALIDATE"] {
            ProjectValidator.runAndExit(path: path)
        }
        if let path = ProcessInfo.processInfo.environment["MSP430IDE_BUILD"] {
            let cfg = ProcessInfo.processInfo.environment["MSP430IDE_CONFIG"] ?? "Debug"
            ProjectValidator.buildAndExit(path: path, configName: cfg)
        }
    }

    var body: some Scene {
        WindowGroup("MSP430 IDE") {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Blink Project…") {
                    appState.createBlinkProject()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Open Project Folder…") {
                    appState.promptOpenProject()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") { appState.saveCurrent() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(appState.selectedFile == nil)

                Button("Save All") { appState.saveAll() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
            }

            CommandMenu("Tabs") {
                Button("Close Tab") {
                    if let url = appState.selectedFile { appState.closeTab(url) }
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(appState.selectedFile == nil)

                Button("Close All Tabs") { appState.closeAllTabs() }
                    .keyboardShortcut("w", modifiers: [.command, .option])
                    .disabled(appState.editor.openTabs.isEmpty)

                Button("Reopen Last Closed") { appState.reopenLastClosed() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Next Tab") { appState.nextTab() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(appState.editor.openTabs.count < 2)

                Button("Previous Tab") { appState.prevTab() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(appState.editor.openTabs.count < 2)

                Divider()

                ForEach(0..<9, id: \.self) { i in
                    Button("Go to Tab \(i + 1)") { appState.selectTabAt(i) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                        .disabled(appState.editor.openTabs.count <= i)
                }
            }

            CommandMenu("Build") {
                Button("Build") {
                    Task { await appState.build() }
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(appState.project == nil || appState.isBuilding)

                Button("Flash") {
                    Task { await appState.flash() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.project == nil || appState.isFlashing)

                Divider()

                Button("Clean Build Folder") {
                    appState.cleanBuild()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
