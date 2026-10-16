import AppKit
import SwiftUI

@main
struct FastMojiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("FastMoji", systemImage: "face.smiling") {
            Button("Quit FastMoji") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
