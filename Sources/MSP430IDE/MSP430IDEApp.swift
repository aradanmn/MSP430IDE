import SwiftUI
import AppKit

@main
struct MSP430IDEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var panels = PanelManager()

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
                .environmentObject(panels)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear {
                    // Let pop-out windows share the same app state.
                    panels.attach(appState: appState)
                    // Workspace persists are debounced; flush on quit so the
                    // last second of state changes isn't lost.
                    appDelegate.onTerminate = { [weak appState] in
                        appState?.flushWorkspaceState()
                    }
                    // Whenever a new build produces diagnostics, flip the
                    // bottom panel to Problems. Auto-switch on any
                    // severity (errors or warnings) per user preference.
                    appState.onDiagnosticsUpdated = { [weak panels] diags in
                        guard !diags.isEmpty else { return }
                        Task { @MainActor [weak panels] in
                            panels?.showPanel(.problems)
                        }
                    }
                    appState.onDebuggerStopped = { [weak panels] in
                        Task { @MainActor [weak panels] in
                            panels?.showPanel(.debugger)
                        }
                    }
                    // Show the debugger panel only while a session is active.
                    appState.onDebugActiveChanged = { [weak panels] active in
                        Task { @MainActor [weak panels] in
                            if active { panels?.reveal(.debugger) } else { panels?.hide(.debugger) }
                        }
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(appState: appState, panels: panels, menu: appState.menu)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (@MainActor () -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        onTerminate?()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Each pop-out is its own window; never let macOS merge them into
        // automatic window tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
