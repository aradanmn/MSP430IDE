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
