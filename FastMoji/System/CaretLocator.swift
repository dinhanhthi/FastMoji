import AppKit
import ApplicationServices

/// Finds the text caret of the focused element via Accessibility.
@MainActor
enum CaretLocator {
    /// `axRect` (from `axCaretRect()`) in AppKit screen coordinates (bottom-left origin).
    /// Falls back to the mouse location (zero size) when it is nil: the focused app does not
    /// expose caret bounds (common in Chromium/Electron/Java apps) or AX was skipped.
    static func screenRect(fromAX axRect: CGRect?) -> NSRect {
        let mouse = NSRect(origin: NSEvent.mouseLocation, size: .zero)
        guard let primary = NSScreen.screens.first, let rect = axRect else { return mouse }
        return NSRect(
            x: rect.minX,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Caret bounds in global top-left-origin coordinates, or nil.
    /// Up to 4 AX round-trips of up to 0.2 s each: call it off the main thread
    /// (AX APIs are thread-safe) so the event tap on the main run loop never stalls.
    nonisolated static func axCaretRect() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        // Applied globally when set on the system-wide element.
        AXUIElementSetMessagingTimeout(systemWide, 0.2)

        guard let focused = attribute(systemWide, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement

        guard let rangeRef = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        let rangeValue = rangeRef as! AXValue
        var range = CFRange()
        guard AXValueGetType(rangeValue) == .cfRange,
              AXValueGetValue(rangeValue, .cfRange, &range)
        else { return nil }

        let primary = bounds(element, rangeValue)
        if range.length == 0, range.location > 0, (primary?.height ?? 0) == 0 {
            // Empty selection often reports zero-height bounds: use the previous character's.
            var previous = CFRange(location: range.location - 1, length: 1)
            if let previousValue = AXValueCreate(.cfRange, &previous),
               let rect = bounds(element, previousValue), rect.height > 0 {
                return CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height)
            }
        }
        return primary
    }

    /// `kAXBoundsForRangeParameterizedAttribute` for `range`, nil on failure or a zero rect at (0,0).
    private nonisolated static func bounds(_ element: AXUIElement, _ range: AXValue) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &value
        ) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = value as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(axValue) == .cgRect,
              AXValueGetValue(axValue, .cgRect, &rect),
              !rect.isNull, !rect.isInfinite,
              !(rect.origin == .zero && rect.size == .zero)
        else { return nil }
        return rect
    }

    private nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
