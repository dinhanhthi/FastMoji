import AppKit
import SwiftUI

@main
struct FastMojiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: appState.menuBarPicker)
        } label: {
            Image(systemName: "face.smiling")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosting unit tests: never quit the user's running copy.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        terminateOtherInstances()
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
