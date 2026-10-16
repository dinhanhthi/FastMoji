import AppKit
import CoreGraphics
import Observation

/// Wires the Accessibility permission, the event tap, the picker panel and the inserter.
/// Created once at launch (never while hosting unit tests, so tests never start the tap).
@MainActor
@Observable
final class AppCoordinator {
    let permission = AccessibilityPermission()

    @ObservationIgnored private let tap = EventTap()
    /// Model of the panel; shares catalog, search and history with the menubar picker.
    @ObservationIgnored private let hotkeyPicker: EmojiPickerModel
    @ObservationIgnored private let panel: PickerPanelController

    /// Settings read on every keystroke, refreshed on `UserDefaults.didChangeNotification`.
    @ObservationIgnored private var hotkey = AppSettings.hotkey
    @ObservationIgnored private var hotkeyEnabled = AppSettings.hotkeyEnabled

    /// App that was frontmost when the panel opened; receives the emoji.
    @ObservationIgnored private var targetApp: NSRunningApplication?
    @ObservationIgnored private var retryPending = false
    /// True while the caret lookup for the next hotkey panel runs off the main thread.
    @ObservationIgnored private var locatingCaret = false
    /// Bumped on every toggle so a lookup that finishes after a second press is dropped.
    @ObservationIgnored private var caretRequest = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let modifierMask = CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskShift.rawValue
    /// Lets the host field take focus back before keys are synthesized.
    private static let insertionDelay: Duration = .milliseconds(80)

    init(appState: AppState) {
        hotkeyPicker = EmojiPickerModel(
            catalog: appState.catalog, search: appState.search, frecency: appState.frecency
        )
        panel = PickerPanelController(model: hotkeyPicker)
        hotkeyPicker.onConfirm = { [weak self] emoji in self?.confirm(emoji) }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settingsChanged() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateTap() }
            },
        ]
        observeTrust()
        updateTap()
    }

    // MARK: - Tap lifecycle

    /// Runs the tap while Accessibility is granted and a tap-driven trigger is enabled.
    private func updateTap() {
        guard permission.isTrusted, hotkeyEnabled else {
            if tap.isRunning { tap.stop() }
            return
        }
        guard !tap.isRunning else { return }
        let started = tap.start { [weak self] type, event in
            self?.handle(type: type, event: event) ?? false
        }
        if !started { scheduleRetry() }
    }

    /// `tapCreate` can fail for a moment right after the grant; try again once a second.
    private func scheduleRetry() {
        guard !retryPending else { return }
        retryPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            self.retryPending = false
            self.updateTap()
        }
    }

    /// Re-evaluates the tap whenever `permission.isTrusted` changes.
    private func observeTrust() {
        withObservationTracking {
            _ = permission.isTrusted
        } onChange: { [weak self] in
            // onChange fires before the new value is stored: read it on the next turn.
            Task { @MainActor in
                self?.updateTap()
                self?.observeTrust()
            }
        }
    }

    private func settingsChanged() {
        hotkey = AppSettings.hotkey
        hotkeyEnabled = AppSettings.hotkeyEnabled
        updateTap()
    }

    // MARK: - Tap handler (main thread, synchronous: decide swallow, dispatch the work)

    /// Returns true to swallow the event.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .keyDown:
            return handleKeyDown(event)
        case .leftMouseDown, .rightMouseDown:
            handleMouseDown()
            return false
        default:
            return false
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = UInt(event.flags.rawValue & Self.modifierMask)

        // `hotkey.isValid`: never swallow plain keystrokes, even if validation upstream fails.
        if hotkeyEnabled, hotkey.isValid, keyCode == hotkey.keyCode, modifiers == hotkey.modifiers {
            // Holding the shortcut must not make the panel flicker.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                DispatchQueue.main.async { [weak self] in self?.toggleHotkeyPanel() }
            }
            return true
        }

        // inline trigger (Phase 4): feed the detector with this key here.
        return false
    }

    /// Mouse events are never swallowed.
    private func handleMouseDown() {
        // inline trigger (Phase 4): reset the detector here.
        guard panel.isVisible, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        DispatchQueue.main.async { [weak self] in self?.panel.hide() }
    }

    // MARK: - Hotkey panel

    /// Pressing the hotkey while the caret lookup runs cancels the opening.
    private func toggleHotkeyPanel() {
        caretRequest += 1
        if locatingCaret || panel.mode == .hotkey {
            locatingCaret = false
            panel.hide()
            return
        }
        targetApp = NSWorkspace.shared.frontmostApplication
        // FastMoji itself frontmost (e.g. its popover): AX on our own main thread would block.
        if targetApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            panel.show(at: CaretLocator.screenRect(fromAX: nil), mode: .hotkey)
            return
        }
        locatingCaret = true
        let request = caretRequest
        Task { @MainActor [weak self] in
            // Off the main run loop, which also serves the event tap.
            let axRect = await Task.detached(priority: .userInitiated) { CaretLocator.axCaretRect() }.value
            guard let self, self.locatingCaret, request == self.caretRequest else { return }
            self.locatingCaret = false
            self.panel.show(at: CaretLocator.screenRect(fromAX: axRect), mode: .hotkey)
        }
    }

    /// Enter or click in the panel; the model has already recorded the pick in the history.
    private func confirm(_ emoji: Emoji) {
        // Phase 4: branch on `panel.mode` (read before hiding) for the inline action and deletion count.
        panel.hide()
        let target = targetApp
        targetApp = nil
        if let target,
           target.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier {
            target.activate()
        }
        Task { @MainActor in
            try? await Task.sleep(for: Self.insertionDelay)
            EmojiInserter.perform(
                AppSettings.hotkeyAction, emoji: emoji.emoji, deleting: 0, method: AppSettings.insertionMethod
            )
        }
    }
}
