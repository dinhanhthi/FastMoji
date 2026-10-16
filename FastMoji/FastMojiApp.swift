import AppKit
import SwiftUI

@main
struct FastMojiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarRoot(appDelegate: appDelegate)
        } label: {
            Image(systemName: "face.smiling")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Reads the delegate inside a view body so the banner appears once the coordinator exists.
private struct MenuBarRoot: View {
    let appDelegate: AppDelegate

    var body: some View {
        MenuBarContentView(
            model: appDelegate.appState.menuBarPicker,
            permission: appDelegate.coordinator?.permission
        )
    }
}

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The only app state; created with the delegate, before SwiftUI first reads it.
    let appState = AppState()
    /// Nil while hosting unit tests (no event tap, no permission polling).
    private(set) var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosting unit tests: never quit the user's running copy.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        terminateOtherInstances()
        coordinator = AppCoordinator(appState: appState)
    }

    /// A fresh launch (Xcode cmd+R or /Applications) replaces any older running copy.
    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where app.processIdentifier != ownPID {
            app.terminate()
        }
    }
}
