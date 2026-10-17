import AppKit
import SwiftUI

/// The one Settings window (not the SwiftUI `Settings` scene, unreliable to open from an
/// LSUIElement app). Every entry point calls `SettingsWindowController.shared.show()`.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var frecency: FrecencyStore?
    private var permission: AccessibilityPermission?
    private var updater: Updater?
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    /// Called once at launch by `AppDelegate` (never while hosting unit tests).
    func configure(frecency: FrecencyStore, permission: AccessibilityPermission, updater: Updater) {
        self.frecency = frecency
        self.permission = permission
        self.updater = updater
    }

    /// Brings the window to the front, creating it on first use.
    func show() {
        guard let window = window ?? makeWindow() else { return }
        // Dock icon only while Settings is open; closing the window hides it again.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // LSUIElement: activation alone does not always raise the window above other apps.
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow? {
        guard let frecency, let permission, let updater else { return nil }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "FastMoji Settings"
        // The sidebar shows the app name; let it run under a transparent title bar.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: SettingsView(frecency: frecency, permission: permission, updater: updater))
        // Keep the fixed window size; the grouped Form scrolls instead of resizing the window.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
        }
        self.window = window
        return window
    }
}
