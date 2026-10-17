import AppKit
import CoreGraphics

/// Puts an emoji into the frontmost app by synthesizing keyboard events.
/// Every posted event is tagged with `tag` so `EventTap` lets it through untouched.
@MainActor
enum EmojiInserter {
    /// "FMOJ", stored in `CGEventField.eventSourceUserData`.
    static let tag: Int64 = 0x464D4F4A

    private static let backspaceKey: CGKeyCode = 51
    private static let vKey: CGKeyCode = 9
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// The backspaces (and, for `.type`, the emoji keystroke) are posted synchronously: called
    /// inside the tap callback, they must precede any key typed after the pick. `.paste` runs its
    /// clipboard work on the next main-queue turn instead, since reading the clipboard can call
    /// into the app that owns it; `isTargetFrontmost` is checked again there, and when the focus
    /// moved meanwhile the emoji is only copied. Accepted trade-off: the backspaces are already
    /// posted by then, so if the focus changed in that one-turn gap the typed trigger is deleted
    /// but the emoji is not inserted (only copied).
    static func perform(
        _ action: PickAction,
        emoji: String,
        deleting n: Int,
        method: InsertionMethod,
        isTargetFrontmost: @escaping @MainActor () -> Bool
    ) {
        guard action != .copy else {
            copy(emoji)
            return
        }
        deleteBackward(n)
        switch method {
        case .type:
            type(emoji)
            if action == .insertAndCopy { copy(emoji) }
        case .paste:
            DispatchQueue.main.async {
                guard isTargetFrontmost() else {
                    copy(emoji)
                    return
                }
                // `.insertAndCopy`: the pasted emoji stays on the clipboard as the user's copy.
                paste(emoji, keepOnClipboard: action == .insertAndCopy)
            }
        }
    }

    static func copy(_ emoji: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(emoji, forType: .string)
    }

    private static func deleteBackward(_ n: Int) {
        for _ in 0..<max(n, 0) {
            postKey(backspaceKey)
        }
    }

    /// One key event per chunk, posted synchronously in order (custom alias text can be long).
    private static func type(_ emoji: String) {
        for chunk in chunks(of: emoji) {
            let utf16 = Array(chunk.utf16)
            postKey(0) { event in
                utf16.withUnsafeBufferPointer {
                    event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress!)
                }
            }
        }
    }

    /// A key event carries at most about 20 UTF-16 units of text; the rest is dropped.
    nonisolated static let maxChunkLength = 20

    /// Splits `text` into chunks of at most `maxChunkLength` UTF-16 units, only between
    /// Characters (never inside a surrogate pair or a ZWJ sequence). A single Character
    /// longer than that (no emoji is) goes alone in its own chunk, possibly truncated.
    nonisolated static func chunks(of text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for char in text {
            if !current.isEmpty, current.utf16.count + char.utf16.count > maxChunkLength {
                chunks.append(current)
                current = ""
            }
            current.append(char)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Pastes via cmd+V. Unless `keepOnClipboard`, the emoji is marked transient and the
    /// previous clipboard is restored after 300 ms (if nothing else changed it meanwhile),
    /// limited to `restorableTypes` plus the original `markerTypes`. When the previous clipboard
    /// held items but none had restorable data, it is not restored (nor cleared): the transient
    /// emoji stays on it.
    private static func paste(_ emoji: String, keepOnClipboard: Bool) {
        let pasteboard = NSPasteboard.general
        let snapshot = keepOnClipboard ? nil : snapshotItems(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(emoji, forType: .string)
        if !keepOnClipboard { pasteboard.setData(Data(), forType: transientType) }
        let changeCount = pasteboard.changeCount

        postKey(vKey, flags: .maskCommand)

        guard let snapshot else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
            if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
        }
    }

    /// Pasteboard types kept across a paste. Restricting reads to these common types reduces,
    /// but does not eliminate, the risk of blocking the main thread: any of them may still be
    /// lazily promised by the owning app, while app-private data and promised files, which
    /// are more likely to be, are skipped.
    private static let restorableTypes: [NSPasteboard.PasteboardType] = [
        .string, .rtf, .html, .URL, .fileURL, .png, .tiff,
    ]
    /// nspasteboard.org markers (concealed, transient, auto-generated, source app), copied
    /// as-is onto the restored item so clipboard managers keep honoring them (e.g. they do not
    /// record a password-manager secret when it is written back).
    private static let markerTypes: [NSPasteboard.PasteboardType] = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "org.nspasteboard.source",
    ].map { NSPasteboard.PasteboardType($0) }
    /// Larger data of a single type is not restored.
    private static let maxRestoredDataSize = 10 * 1024 * 1024

    /// Copy of the `restorableTypes` data (plus `markerTypes`) of every item on `pasteboard`;
    /// items without restorable data are dropped. `[]` when the pasteboard is empty, `nil` when
    /// it has items but none survive (nothing worth restoring).
    private static func snapshotItems(of pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
        let items = pasteboard.pasteboardItems ?? []
        let copies: [NSPasteboardItem] = items.compactMap { item in
            let copy = NSPasteboardItem()
            var isEmpty = true
            for type in item.types where restorableTypes.contains(type) {
                guard let data = item.data(forType: type), data.count <= maxRestoredDataSize else { continue }
                copy.setData(data, forType: type)
                isEmpty = false
            }
            guard !isEmpty else { return nil }
            for type in item.types where markerTypes.contains(type) {
                copy.setData(item.data(forType: type) ?? Data(), forType: type)
            }
            return copy
        }
        return !items.isEmpty && copies.isEmpty ? nil : copies
    }

    /// Posts a tagged keyDown + keyUp pair to the HID event tap.
    private static func postKey(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        configure: (CGEvent) -> Void = { _ in }
    ) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: tag)
            configure(event)
            event.post(tap: .cghidEventTap)
        }
    }
}
