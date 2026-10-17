import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Observation

/// Wires the Accessibility permission, the event tap, the picker panel and the inserter.
/// Created once at launch (never while hosting unit tests, so tests never start the tap).
@MainActor
@Observable
final class AppCoordinator {
    let permission = AccessibilityPermission()

    @ObservationIgnored private let tap = EventTap()
    @ObservationIgnored private let frecency: FrecencyStore
    /// Model of the panel; shares catalog, search and history with the menubar picker.
    @ObservationIgnored private let picker: EmojiPickerModel
    /// One panel for the hotkey and inline triggers, which are never visible together:
    /// each SwiftUI tree costs several MB, kept for the app's lifetime.
    @ObservationIgnored private let panel: PickerPanelController

    /// Settings read on every keystroke, refreshed on `UserDefaults.didChangeNotification`.
    @ObservationIgnored private var hotkey = AppSettings.hotkey
    @ObservationIgnored private var hotkeyEnabled = AppSettings.hotkeyEnabled
    @ObservationIgnored private var inlineEnabled = AppSettings.inlineEnabled
    @ObservationIgnored private var triggerSequence = AppSettings.triggerSequence
    @ObservationIgnored private var triggerWindowMs = AppSettings.triggerWindowMs
    @ObservationIgnored private var ignoredApps = Set(AppSettings.ignoredApps)
    @ObservationIgnored private var ignoredDomains = AppSettings.ignoredDomains
    @ObservationIgnored private var detector: TriggerDetector

    /// App that was frontmost when a panel opened; receives the emoji.
    @ObservationIgnored private var targetApp: NSRunningApplication?
    /// Last app other than FastMoji to become frontmost; receives menubar picks.
    @ObservationIgnored private var lastExternalApp: NSRunningApplication?
    @ObservationIgnored private var retryPending = false
    /// Panel whose caret lookup runs off the main thread, nil when none.
    @ObservationIgnored private var locatingCaret: PickerMode?
    /// Bumped on every lookup and cancel so a lookup that finishes late is dropped.
    @ObservationIgnored private var caretRequest = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Bumped per panel opening: a late web host lookup never retargets a newer panel.
    @ObservationIgnored private var ignoreRequest = 0

    private static let modifierMask = CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskShift.rawValue
    /// Modifiers that turn a keystroke into a shortcut: such keys never belong to a query.
    private static let shortcutMask = CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskControl.rawValue
    /// Lets the host field take focus back before keys are synthesized.
    private static let insertionDelay: Duration = .milliseconds(80)

    /// Virtual key codes (`kVK_*`).
    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let backspace: UInt16 = 51
        static let escape: UInt16 = 53
        static let enter: UInt16 = 76
        static let home: UInt16 = 115
        static let pageUp: UInt16 = 116
        static let forwardDelete: UInt16 = 117
        static let end: UInt16 = 119
        static let pageDown: UInt16 = 121
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    init(appState: AppState) {
        frecency = appState.frecency
        picker = EmojiPickerModel(
            catalog: appState.catalog, search: appState.search, frecency: appState.frecency
        )
        panel = PickerPanelController(model: picker)
        detector = Self.makeDetector(sequence: AppSettings.triggerSequence, windowMs: AppSettings.triggerWindowMs)

        picker.onConfirm = { [weak self] emoji in
            guard let self else { return }
            if self.panel.mode == .inline {
                self.confirmInline(emoji)
            } else {
                self.confirmHotkey(emoji)
            }
        }
        rememberExternalApp()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settingsChanged() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateTap() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.rememberExternalApp()
                    self?.closeInline()
                }
            },
        ]
        observeTrust()
        updateTap()
    }

    private static func makeDetector(sequence: String, windowMs: Int) -> TriggerDetector {
        TriggerDetector(sequence: sequence, keyWindow: TimeInterval(windowMs) / 1000)
    }

    // MARK: - Tap lifecycle

    /// Runs the tap while Accessibility is granted and a tap-driven trigger is enabled.
    private func updateTap() {
        // `AXIsProcessTrusted()` too: `permission` stops polling once trusted, so it misses a revoke.
        guard permission.isTrusted, AXIsProcessTrusted(), inlineEnabled || hotkeyEnabled else {
            if tap.isRunning { tap.stop() }
            closeInline()
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

    /// Also fires for every frecency save: only rebuild the detector when its settings changed.
    private func settingsChanged() {
        hotkey = AppSettings.hotkey
        hotkeyEnabled = AppSettings.hotkeyEnabled

        let enabled = AppSettings.inlineEnabled
        let sequence = AppSettings.triggerSequence
        let windowMs = AppSettings.triggerWindowMs
        if enabled != inlineEnabled || sequence != triggerSequence || windowMs != triggerWindowMs {
            closeInline()
            if sequence != triggerSequence || windowMs != triggerWindowMs {
                detector = Self.makeDetector(sequence: sequence, windowMs: windowMs)
            }
            inlineEnabled = enabled
            triggerSequence = sequence
            triggerWindowMs = windowMs
        }

        let apps = Set(AppSettings.ignoredApps)
        if apps != ignoredApps {
            closeInline()
            ignoredApps = apps
        }
        let domains = AppSettings.ignoredDomains
        if domains != ignoredDomains {
            // The panel's Ignore button: stop the query typed on the newly ignored website.
            closeInline()
            ignoredDomains = domains
        }
        updateTap()
    }

    // MARK: - Tap handler (main thread, synchronous: decide swallow, dispatch the work)

    /// Returns true to swallow the event. Keystrokes are never logged or stored.
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
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        // Ignored app: every key reaches it untouched, the hotkey included.
        // Not while the hotkey panel is open: its keys belong to FastMoji.
        if !ignoredApps.isEmpty, panel.mode != .hotkey,
           let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           ignoredApps.contains(bundleID) {
            closeInline()
            return false
        }

        // `hotkey.isValid`: never swallow plain keystrokes, even if validation upstream fails.
        // While Settings records a new shortcut, the current one must reach its key monitor.
        if hotkeyEnabled, !ShortcutRecorderView.isRecording, hotkey.isValid,
           keyCode == hotkey.keyCode, modifiers == hotkey.modifiers {
            // Holding the shortcut must not make the panel flicker.
            if !isRepeat {
                closeInline()
                DispatchQueue.main.async { [weak self] in self?.toggleHotkeyPanel() }
            }
            return true
        }

        guard inlineEnabled else { return false }
        return handleInlineKey(event, keyCode: keyCode, isRepeat: isRepeat)
    }

    /// Feeds the trigger detector; swallows only navigation / confirm keys of a visible inline panel.
    private func handleInlineKey(_ event: CGEvent, keyCode: UInt16, isRepeat: Bool) -> Bool {
        // Typed into FastMoji's own windows (hotkey panel, menubar popover): not a host-app trigger.
        if panel.mode == .hotkey || NSApp.isActive || NSApp.keyWindow != nil {
            closeInline()
            return false
        }
        if event.flags.rawValue & Self.shortcutMask != 0 {
            closeInline()
            return false
        }
        if panel.mode == .inline, let swallow = handleVisibleInlineKey(keyCode) {
            return swallow
        }
        // A held key never starts or extends a query.
        if isRepeat {
            closeInline()
            return false
        }

        switch keyCode {
        case KeyCode.space, KeyCode.returnKey, KeyCode.enter:
            feed(.boundary(at: Date()))
        case KeyCode.backspace:
            feed(.backspace(at: Date()))
        // Tab may autocomplete (e.g. `std` -> `std::`): what precedes the caret is unknown.
        case KeyCode.left, KeyCode.right, KeyCode.down, KeyCode.up,
             KeyCode.home, KeyCode.end, KeyCode.pageUp, KeyCode.pageDown,
             KeyCode.forwardDelete, KeyCode.escape, KeyCode.tab:
            closeInline()
        default:
            feedCharacters(of: event)
        }
        return false
    }

    /// Keys with a special meaning while the inline panel is visible; nil for the others.
    private func handleVisibleInlineKey(_ keyCode: UInt16) -> Bool? {
        switch keyCode {
        case KeyCode.left: moveInline(.left)
        case KeyCode.right: moveInline(.right)
        case KeyCode.up: moveInline(.up)
        case KeyCode.down: moveInline(.down)
        case KeyCode.escape:
            closeInline()
        case KeyCode.returnKey, KeyCode.enter, KeyCode.tab:
            return pickInlineSelection(keyCode)
        default:
            return nil
        }
        return true
    }

    private func moveInline(_ direction: MoveDirection) {
        applyInlineQuery()
        picker.move(direction)
    }

    /// Return / Enter / Tab: picks the selection when there is one the user asked for,
    /// otherwise closes and lets the key through (e.g. `::` + Return is a plain newline).
    private func pickInlineSelection(_ keyCode: UInt16) -> Bool {
        // Switched to an input method mid-query: the typed length is unknown, delete nothing.
        if Self.isInputMethodActive() {
            closeInline()
            return false
        }
        // A query update may still be queued: the pick must match what was typed.
        applyInlineQuery()
        guard let emoji = picker.selectedEmoji,
              !detector.query.isEmpty || picker.hasMoved
        else {
            if keyCode == KeyCode.tab {
                closeInline()
            } else {
                // The newline reaches the host: a trigger may start right after it.
                hideInline()
                feed(.boundary(at: Date()))
            }
            return false
        }
        let typedLength = detector.typedLength
        closeInline()
        // The backspaces are posted inside the tap callback, before the swallowed key returns:
        // the host app kept the focus (the inline panel never activates), and no key typed after
        // the pick can reach the host before them. A paste follows on the next main-queue turn.
        deliver(emoji, action: AppSettings.inlineAction, deleting: typedLength, immediately: true)
        // History is saved as JSON: out of the tap callback.
        DispatchQueue.main.async { [weak self] in self?.frecency.record(emoji.emoji) }
        return true
    }

    private func feedCharacters(of event: CGEvent) {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer
        )
        let text = String(utf16CodeUnits: buffer, count: min(length, buffer.count))
        // Dead keys and keys without text: the host text is unknown from here on.
        guard !text.isEmpty else {
            closeInline()
            return
        }
        let now = Date()
        for char in text {
            feed(.char(char, at: now))
        }
    }

    private func feed(_ input: TriggerDetector.Input) {
        switch detector.feed(input) {
        case .none:
            break
        case .open:
            DispatchQueue.main.async { [weak self] in self?.openInline() }
        case .query:
            // Searching is the costly part: kept out of the tap callback here. A pick or a move
            // may still run it synchronously (`applyInlineQuery`), cheap for ~1.8k entries.
            DispatchQueue.main.async { [weak self] in self?.applyInlineQuery() }
        case .close:
            hideInline()
        }
    }

    /// Mouse events are never swallowed.
    private func handleMouseDown() {
        let mouse = NSEvent.mouseLocation
        // A click on an inline cell confirms via `onConfirm`, which still needs the typed length.
        if panel.mode == .inline, panel.frame.contains(mouse) { return }
        cancelCaretLookup()
        closeInline()
        guard panel.mode == .hotkey, !panel.frame.contains(mouse) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.mode == .hotkey else { return }
            self.panel.hide()
        }
    }

    // MARK: - Caret lookup

    /// Locates the caret off the main thread, then shows the panel for `mode`
    /// unless the lookup was cancelled or superseded meanwhile.
    private func locateCaret(for mode: PickerMode) {
        caretRequest += 1
        let request = caretRequest
        locatingCaret = mode
        // Ignored domains only turn the inline trigger off: the hotkey still works there.
        let domains = mode == .inline ? ignoredDomains : []
        Task { @MainActor [weak self] in
            // Off the main run loop, which also serves the event tap.
            // `CaretLocator.axCaretRect` must stay read-only: it runs while the user keeps typing.
            let lookup = await Task.detached(priority: .userInitiated) { () -> CaretLookup? in
                if !domains.isEmpty, let host = CaretLocator.focusedWebHost(),
                   AppSettings.isIgnored(host: host, domains: domains) {
                    return nil
                }
                return CaretLocator.axCaretRect()
            }.value
            guard let self, self.locatingCaret == mode, request == self.caretRequest else { return }
            self.locatingCaret = nil
            // Ignored domain: reset the detector so it stops collecting a query.
            guard let lookup else {
                self.closeInline()
                return
            }
            let caret = CaretLocator.screenRect(fromAX: lookup)
            switch mode {
            case .hotkey: self.showHotkeyPanel(at: caret)
            case .inline: self.showInlinePanel(at: caret)
            }
        }
    }

    private func cancelCaretLookup() {
        caretRequest += 1
        locatingCaret = nil
    }

    // MARK: - Hotkey panel

    /// Pressing the hotkey while the caret lookup runs cancels the opening.
    private func toggleHotkeyPanel() {
        if locatingCaret == .hotkey || panel.mode == .hotkey {
            cancelCaretLookup()
            panel.hide()
            return
        }
        closeInline()
        targetApp = NSWorkspace.shared.frontmostApplication
        // FastMoji itself frontmost (e.g. its menubar popover): there is no host caret to find,
        // and a pick is copied instead of inserted (see `deliver`).
        if targetApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            cancelCaretLookup()
            showHotkeyPanel(at: CaretLocator.screenRect(fromAX: .none))
            return
        }
        locateCaret(for: .hotkey)
    }

    private func showHotkeyPanel(at caret: NSRect) {
        closeInline()
        panel.show(at: caret, mode: .hotkey)
        resolveIgnoreTarget()
    }

    /// The Ignore button offers the target app, or the website when the caret is in a web page.
    /// The host lookup walks AX ancestors: done after the panel shows, so it never delays it.
    private func resolveIgnoreTarget() {
        ignoreRequest += 1
        let request = ignoreRequest
        guard let app = targetApp, let bundleID = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        panel.setIgnoreTarget(.app(bundleID: bundleID, name: app.localizedName ?? bundleID))
        Task { @MainActor [weak self] in
            let host = await Task.detached(priority: .userInitiated) { CaretLocator.focusedWebHost() }.value
            guard let self, request == self.ignoreRequest, self.panel.mode != nil,
                  let domain = host.flatMap(AppSettings.normalizedDomain) else { return }
            // Already ignored (the hotkey still works there): nothing left to offer.
            let ignored = AppSettings.isIgnored(host: domain, domains: self.ignoredDomains)
            self.panel.setIgnoreTarget(ignored ? nil : .domain(domain))
        }
    }

    /// Enter or click in the hotkey panel; the model has already recorded the pick in the history.
    private func confirmHotkey(_ emoji: Emoji) {
        panel.hide()
        deliver(emoji, action: AppSettings.hotkeyAction, deleting: 0)
    }

    // MARK: - Inline panel

    /// The detector saw the trigger sequence (async, outside the tap callback).
    private func openInline() {
        // A hotkey caret lookup in flight keeps its panel: never replace it with the inline one.
        guard detector.isActive, panel.mode != .hotkey, locatingCaret != .hotkey else { return }
        // Input methods (Vietnamese Telex, Pinyin, ...) compose text in the host app: the tap sees
        // raw keys, so the query and the deletion count would be wrong. Hotkey + menubar still work.
        if Self.isInputMethodActive() {
            _ = detector.feed(.reset)
            return
        }
        targetApp = NSWorkspace.shared.frontmostApplication
        locateCaret(for: .inline)
    }

    private func showInlinePanel(at caret: NSRect) {
        // Closed while the caret was located (space, click, app switch, ...).
        guard detector.isActive, panel.mode != .hotkey else { return }
        panel.show(at: caret, mode: .inline)
        // `show` resets the model: re-apply what was typed during the lookup.
        applyInlineQuery()
        resolveIgnoreTarget()
    }

    /// Mirrors the detector's query into the visible inline panel (no-op search if unchanged).
    private func applyInlineQuery() {
        guard panel.mode == .inline, detector.isActive else { return }
        picker.query = detector.query.lowercased()
        panel.setInlineQuery(triggerSequence + detector.query)
    }

    /// Hides the inline panel (or cancels its pending opening) without touching the detector.
    /// Never hides the panel in hotkey mode.
    private func hideInline() {
        if locatingCaret == .inline { cancelCaretLookup() }
        if panel.mode == .inline { panel.hide() }
    }

    /// Resets the detector and hides the inline panel; the host text is left as typed.
    private func closeInline() {
        _ = detector.feed(.reset)
        hideInline()
    }

    /// Click on a cell of the inline panel; the model has already recorded the pick in the history.
    private func confirmInline(_ emoji: Emoji) {
        let typedLength = detector.typedLength
        closeInline()
        // Switched to an input method mid-query: the typed length is unknown, copy instead.
        if Self.isInputMethodActive() {
            targetApp = nil
            EmojiInserter.copy(emoji.toned(AppSettings.skinTone))
            return
        }
        deliver(emoji, action: AppSettings.inlineAction, deleting: typedLength, immediately: true)
    }

    // MARK: - Menubar

    /// Called on every activation: the menubar popover may activate FastMoji itself.
    private func rememberExternalApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        lastExternalApp = app
    }

    /// Enter or click in the menubar popover (already closed); the model has recorded the pick.
    /// Inserts into the app that was frontmost before the popover, copies when there is none.
    func deliverMenubarPick(_ emoji: Emoji) {
        let action = AppSettings.menubarAction
        guard action != .copy, AXIsProcessTrusted(), let app = lastExternalApp, !app.isTerminated else {
            EmojiInserter.copy(emoji.toned(AppSettings.skinTone))
            return
        }
        targetApp = app
        deliver(emoji, action: action, deleting: 0)
    }

    // MARK: - Delivery

    /// Puts `emoji` into `targetApp` after deleting `count` typed characters (none for `.copy`).
    /// `immediately`: `targetApp` still has the focus (inline panel), skip the reactivation delay.
    private func deliver(_ emoji: Emoji, action: PickAction, deleting count: Int, immediately: Bool = false) {
        let target = targetApp
        targetApp = nil
        // Picked from FastMoji's own window: there is no host field. Without Accessibility the
        // synthesized keys are dropped. No target: nowhere safe to type. Copy so the emoji is not lost.
        guard action != .copy, let target, AXIsProcessTrusted(),
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            EmojiInserter.copy(emoji.toned(AppSettings.skinTone))
            return
        }
        if immediately {
            Self.perform(action, emoji: emoji, deleting: count, into: target)
            return
        }
        if target.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier {
            target.activate()
        }
        Task { @MainActor in
            try? await Task.sleep(for: Self.insertionDelay)
            Self.perform(action, emoji: emoji, deleting: count, into: target)
        }
    }

    /// Synthesizes the keys only if `target` is (still) frontmost, copies otherwise:
    /// a focus change since the pick must never send backspaces to another app.
    /// Checked again before a deferred paste (see `EmojiInserter.perform`).
    private static func perform(_ action: PickAction, emoji: Emoji, deleting count: Int, into target: NSRunningApplication) {
        let isTargetFrontmost: @MainActor () -> Bool = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
        }
        guard isTargetFrontmost() else {
            EmojiInserter.copy(emoji.toned(AppSettings.skinTone))
            return
        }
        EmojiInserter.perform(
            action, emoji: emoji.toned(AppSettings.skinTone), deleting: count,
            method: AppSettings.insertionMethod, isTargetFrontmost: isTargetFrontmost
        )
    }

    /// True when an input method or input mode (not a plain keyboard layout) is selected.
    private static func isInputMethodActive() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType)
        else { return false }
        let type = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue()
        return !CFEqual(type, kTISTypeKeyboardLayout)
    }
}
