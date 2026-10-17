import AppKit
import SwiftUI

@main
struct FastMojiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    /// Menubar trigger on/off (Settings); off removes the status item.
    @AppStorage(AppSettings.Key.menubarEnabled) private var menubarEnabled = true

    var body: some Scene {
        MenuBarExtra(isInserted: $menubarEnabled) {
            MenuBarRoot(appDelegate: appDelegate)
        } label: {
            MenuBarLabel(appDelegate: appDelegate)
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
            coordinator: appDelegate.coordinator,
            updater: appDelegate.updater
        )
    }
}

/// Status item icon: the logo, dimmed while paused, with a lock badge while Secure Input is on.
/// Composed as one NSImage: the status item keeps only the label's image, not SwiftUI modifiers.
private struct MenuBarLabel: View {
    let appDelegate: AppDelegate

    var body: some View {
        // Read in the body so the label updates once the coordinator exists and on each change.
        let paused = appDelegate.coordinator?.isPaused ?? false
        let secure = appDelegate.coordinator?.secureInput.isOn ?? false
        if paused || secure {
            Image(nsImage: Self.icon(dimmed: paused, locked: secure && !paused))
        } else {
            Image(.menuBarIcon)
        }
    }

    /// Drawn lazily at draw time, so the badge color follows the menubar appearance.
    private static func icon(dimmed: Bool, locked: Bool) -> NSImage {
        let logo = NSImage(resource: .menuBarIcon)
        return NSImage(size: logo.size, flipped: false) { rect in
            logo.draw(in: rect, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.4 : 1)
            guard locked,
                  let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
                      .withSymbolConfiguration(.init(paletteColors: [.labelColor])) else { return true }
            let height = rect.height / 2
            let width = height * lock.size.width / max(lock.size.height, 1)
            let badge = NSRect(x: rect.maxX - width, y: rect.minY, width: width, height: height)
            // Clear a margin around the badge so the lock stays readable on the colored logo.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setFill()
            NSBezierPath(roundedRect: badge.insetBy(dx: -1, dy: -1), xRadius: 2, yRadius: 2).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            lock.draw(in: badge)
            return true
        }
    }
}

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The only app state; created with the delegate, before SwiftUI first reads it.
    let appState = AppState()
    let updater = Updater()
    /// Nil while hosting unit tests (no event tap, no permission polling).
    private(set) var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosting unit tests: never quit the user's running copy.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        terminateOtherInstances()
        let coordinator = AppCoordinator(appState: appState)
        self.coordinator = coordinator
        SettingsWindowController.shared.configure(frecency: appState.frecency, permission: coordinator.permission,
                                                  updater: updater)
        WelcomeWindowController.shared.configure(permission: coordinator.permission)
        // Once per install: new users and 0.1.x upgraders alike (the key defaults to false).
        if !AppSettings.welcomeShown {
            AppSettings.welcomeShown = true
            WelcomeWindowController.shared.show()
        }
        updater.start()
    }

    /// Reopening the app (Finder, Spotlight, `open`) shows Settings: the way back when the menubar is off.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
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
