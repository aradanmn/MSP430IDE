import SwiftUI
import AppKit

@main
struct MSP430IDEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // Plain lets, NOT @StateObject: the App struct is created once per
    // process, so lifetime doesn't need the wrapper — and @StateObject
    // would subscribe the scene body to every objectWillChange, which on
    // macOS rebuilds the menu bar and closes any open menu (the submenu
    // flicker bug). Views observe these via @EnvironmentObject.
    private let appState: AppState
    private let panels: PanelManager
    // The one thing the scene body does observe: deduplicated menu state.
    // Menus rebuild exactly when a menu-relevant fact changes, never from
    // console/diagnostic churn.
    @ObservedObject private var menu: MenuState

    init() {
        if let path = ProcessInfo.processInfo.environment["MSP430IDE_VALIDATE"] {
            ProjectValidator.runAndExit(path: path)
        }
        if let path = ProcessInfo.processInfo.environment["MSP430IDE_BUILD"] {
            let cfg = ProcessInfo.processInfo.environment["MSP430IDE_CONFIG"] ?? "Debug"
            ProjectValidator.buildAndExit(path: path, configName: cfg)
        }
        let state = AppState()
        appState = state
        panels = PanelManager()
        _menu = ObservedObject(wrappedValue: state.menu)
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
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(appState: appState, panels: panels, menu: appState.menu)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Each pop-out is its own window; never let macOS merge them into
        // automatic window tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
