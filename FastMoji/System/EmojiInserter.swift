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

    static func perform(_ action: PickAction, emoji: String, deleting n: Int, method: InsertionMethod) {
        switch action {
        case .insert:
            insert(emoji, deleting: n, method: method)
        case .copy:
            copy(emoji)
        case .insertAndCopy:
            if method == .paste {
                // The pasted emoji stays on the clipboard as the user's copy.
                deleteBackward(n)
                paste(emoji, keepOnClipboard: true)
            } else {
                insert(emoji, deleting: n, method: method)
                copy(emoji)
            }
        }
    }

    /// Deletes `n` characters before the caret, then inserts `emoji`.
    static func insert(_ emoji: String, deleting n: Int, method: InsertionMethod) {
        deleteBackward(n)
        switch method {
        case .type: type(emoji)
        case .paste: paste(emoji, keepOnClipboard: false)
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

    private static func type(_ emoji: String) {
        let utf16 = Array(emoji.utf16)
        postKey(0) { event in
            utf16.withUnsafeBufferPointer {
                event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress!)
            }
        }
    }

    /// Pastes via cmd+V. Unless `keepOnClipboard`, the emoji is marked transient and the
    /// previous clipboard is restored after 300 ms (if nothing else changed it meanwhile).
    private static func paste(_ emoji: String, keepOnClipboard: Bool) {
        let pasteboard = NSPasteboard.general
        let snapshot = keepOnClipboard ? [] : snapshotItems(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(emoji, forType: .string)
        if !keepOnClipboard { pasteboard.setData(Data(), forType: transientType) }
        let changeCount = pasteboard.changeCount

        postKey(vKey, flags: .maskCommand)

        guard !keepOnClipboard else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
            if !snapshot.isEmpty { pasteboard.writeObjects(snapshot) }
        }
    }

    /// Deep copy of every item and type currently on `pasteboard`.
    private static func snapshotItems(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
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
