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
    private(set) var window: NSWindow?
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
        // Dock icon only while Settings (or Welcome) is open; closing the last one hides it again.
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
        ) { note in
            MainActor.assumeIsolated { Self.hideDockIcon(closing: note.object as? NSWindow) }
        }
        self.window = window
        return window
    }

    /// Hides the Dock icon again, unless the other FastMoji window (Settings, Welcome) is still
    /// open. Called on `willClose`, while `closing` is still visible. Listed explicitly rather than
    /// scanning `NSApp.windows`: the status item and the menubar popover have windows too.
    static func hideDockIcon(closing: NSWindow?) {
        let othersOpen = [SettingsWindowController.shared.window, WelcomeWindowController.shared.window]
            .contains { $0 !== closing && $0?.isVisible == true }
        if !othersOpen { NSApp.setActivationPolicy(.accessory) }
    }
}
