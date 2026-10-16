import AppKit
import SwiftUI

/// Button that records a new global hotkey: click, then press the combination (Esc cancels).
struct ShortcutRecorderView: View {
    @Binding var shortcut: KeyShortcut

    /// Read by the event tap: while true it never matches the hotkey and lets every key through,
    /// so the local monitor also sees the current hotkey.
    static private(set) var isRecording = false

    @State private var recorder = Recorder()

    var body: some View {
        HStack(spacing: 8) {
            if recorder.showsHint {
                Text("Use ⌘, ⌥ or ⌃")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                if recorder.isActive {
                    recorder.stop()
                } else {
                    recorder.start { shortcut = $0 }
                }
            } label: {
                Text(recorder.isActive ? "Type shortcut…" : shortcut.label)
                    .frame(minWidth: 100)
            }
        }
        .onDisappear { recorder.stop() }
        // Settings closed or another window took the keyboard: a stale recording would block the hotkey.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            recorder.stop()
        }
    }

    /// Owns the local key monitor and the `isRecording` flag, so both are always reset together.
    @MainActor
    @Observable
    final class Recorder {
        private(set) var isActive = false
        private(set) var showsHint = false

        @ObservationIgnored private var monitor: Any?
        @ObservationIgnored private var onRecord: ((KeyShortcut) -> Void)?
        @ObservationIgnored private var hintTask: Task<Void, Never>?
        @ObservationIgnored private var timeoutTask: Task<Void, Never>?

        /// The recording one, if any: only one records at a time.
        private static weak var current: Recorder?
        /// A forgotten recording would keep the hotkey disabled.
        private static let timeout: Duration = .seconds(10)

        private static let escape: UInt16 = 53
        private static let space: UInt16 = 49
        private static let functionKeys: [NSEvent.SpecialKey] = [
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
        ]

        func start(onRecord: @escaping (KeyShortcut) -> Void) {
            guard monitor == nil else { return }
            if Self.current !== self { Self.current?.stop() }
            Self.current = self
            self.onRecord = onRecord
            isActive = true
            ShortcutRecorderView.isRecording = true
            // Every keyDown is consumed (nil) so e.g. cmd+W or cmd+Q is recorded, not performed.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }
                return nil
            }
            armTimeout()
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            onRecord = nil
            hintTask?.cancel()
            timeoutTask?.cancel()
            timeoutTask = nil
            if Self.current === self { Self.current = nil }
            showsHint = false
            isActive = false
            ShortcutRecorderView.isRecording = false
        }

        private func handle(_ event: NSEvent) {
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == Self.escape, flags.isEmpty {
                stop()
                return
            }
            let shortcut = KeyShortcut(
                keyCode: event.keyCode,
                modifiers: flags.rawValue,
                label: Self.symbols(flags) + Self.keyName(event)
            )
            guard shortcut.isValid else {
                flashHint()
                armTimeout()
                return
            }
            onRecord?(shortcut)
            stop()
        }

        /// Stops after `timeout` without a key.
        private func armTimeout() {
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.timeout)
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        }

        private func flashHint() {
            showsHint = true
            hintTask?.cancel()
            hintTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self?.showsHint = false
            }
        }

        /// Modifier symbols in the standard macOS order.
        private static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
            var text = ""
            if flags.contains(.control) { text += "⌃" }
            if flags.contains(.option) { text += "⌥" }
            if flags.contains(.shift) { text += "⇧" }
            if flags.contains(.command) { text += "⌘" }
            return text
        }

        private static func keyName(_ event: NSEvent) -> String {
            if event.keyCode == space { return "Space" }
            if event.keyCode == escape { return "⎋" }
            if let special = event.specialKey, let name = specialName(special) { return name }
            // Without modifiers applied: shift+; is labelled ";" (with ⇧), not ":".
            let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
            let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return trimmed.isEmpty ? "Key \(event.keyCode)" : trimmed
        }

        private static func specialName(_ key: NSEvent.SpecialKey) -> String? {
            if let index = functionKeys.firstIndex(of: key) { return "F\(index + 1)" }
            switch key {
            case .carriageReturn, .newline: return "↩"
            case .enter: return "⌤"
            case .tab, .backTab: return "⇥"
            case .delete, .backspace: return "⌫"
            case .deleteForward: return "⌦"
            case .upArrow: return "↑"
            case .downArrow: return "↓"
            case .leftArrow: return "←"
            case .rightArrow: return "→"
            case .home: return "↖"
            case .end: return "↘"
            case .pageUp: return "⇞"
            case .pageDown: return "⇟"
            default: return nil
            }
        }
    }
}
