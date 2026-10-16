import AppKit
import SwiftUI

/// The one Settings window (not the SwiftUI `Settings` scene, unreliable to open from an
/// LSUIElement app). Every entry point calls `SettingsWindowController.shared.show()`.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var frecency: FrecencyStore?
    private var permission: AccessibilityPermission?
    private var window: NSWindow?

    private init() {}

    /// Called once at launch by `AppDelegate` (never while hosting unit tests).
    func configure(frecency: FrecencyStore, permission: AccessibilityPermission) {
        self.frecency = frecency
        self.permission = permission
    }

    /// Brings the window to the front, creating it on first use.
    func show() {
        guard let window = window ?? makeWindow() else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // LSUIElement: activation alone does not always raise the window above other apps.
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow? {
        guard let frecency, let permission else { return nil }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FastMoji Settings"
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: SettingsView(frecency: frecency, permission: permission))
        // Keep the fixed window size; the grouped Form scrolls instead of resizing the window.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center()
        self.window = window
        return window
    }
}
