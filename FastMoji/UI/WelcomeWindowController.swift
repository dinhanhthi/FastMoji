import AppKit
import SwiftUI

/// The welcome window: shown once at first launch (`AppSettings.welcomeShown`) and from Settings.
/// Its test field is the only place where FastMoji's own window acts as a host app for the
/// inline trigger (see `isTestFieldFocused`).
@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()

    private var permission: AccessibilityPermission?
    private(set) var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    /// Called once at launch by `AppDelegate` (never while hosting unit tests).
    func configure(permission: AccessibilityPermission) {
        self.permission = permission
    }

    /// Brings the window to the front, creating it on first use.
    func show() {
        guard let window = window ?? makeWindow() else { return }
        // Dock icon while a FastMoji window is open, as for Settings.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // LSUIElement: activation alone does not always raise the window above other apps.
        window.orderFrontRegardless()
    }

    /// True while the welcome window is key and its test field is being edited. The window has a
    /// single text field, so its field editor (an `NSTextView`) being first responder means the
    /// test field has the focus. Read in the tap callback: cheap, main thread.
    var isTestFieldFocused: Bool {
        guard let window, NSApp.keyWindow === window else { return false }
        return window.firstResponder is NSTextView
    }

    private func makeWindow() -> NSWindow? {
        guard let permission else { return nil }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to FastMoji"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: WelcomeView(permission: permission))
        // Keep the fixed window size; the content scrolls instead of resizing the window.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.center()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { note in
            MainActor.assumeIsolated { SettingsWindowController.hideDockIcon(closing: note.object as? NSWindow) }
        }
        self.window = window
        return window
    }
}
