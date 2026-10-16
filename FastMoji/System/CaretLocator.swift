import AppKit
import ApplicationServices

/// Result of `CaretLocator.axCaretRect()`, in global top-left-origin coordinates.
enum CaretLookup: Sendable {
    /// Plausible caret bounds.
    case caret(CGRect)
    /// No plausible caret, but the focused element is a small (single-line-ish) text field.
    case field(CGRect)
    /// Nothing usable.
    case none
}

/// Finds the text caret of the focused element via Accessibility.
@MainActor
enum CaretLocator {
    /// `lookup` (from `axCaretRect()`) in AppKit screen coordinates (bottom-left origin).
    /// A `.field` maps to its full frame (zero width), so the panel opens below it, or above it
    /// without covering it when there is no room below. Falls back to the mouse location (zero size) for `.none` (the focused app does not
    /// expose caret bounds, or AX was skipped) or when the point lies on no screen.
    static func screenRect(fromAX lookup: CaretLookup) -> NSRect {
        let mouse = NSRect(origin: NSEvent.mouseLocation, size: .zero)
        guard let primary = NSScreen.screens.first else { return mouse }
        let rect: NSRect
        switch lookup {
        case .caret(let caret):
            rect = NSRect(
                x: caret.minX,
                y: primary.frame.maxY - caret.maxY,
                width: caret.width,
                height: caret.height
            )
        case .field(let field):
            rect = NSRect(x: field.minX, y: primary.frame.maxY - field.maxY, width: 0, height: field.height)
        case .none:
            return mouse
        }
        guard NSScreen.screens.contains(where: { NSMouseInRect(rect.origin, $0.frame, false) })
        else { return mouse }
        return rect
    }

    /// Caret bounds (or the focused field's frame) in global top-left-origin coordinates.
    /// Up to 6 AX round-trips of up to 0.2 s each: call it off the main thread
    /// (AX APIs are thread-safe) so the event tap on the main run loop never stalls.
    /// Read-only: it never sets AX attributes.
    nonisolated static func axCaretRect() -> CaretLookup {
        let systemWide = AXUIElementCreateSystemWide()
        // Applied globally when set on the system-wide element.
        AXUIElementSetMessagingTimeout(systemWide, 0.2)

        guard let focused = attribute(systemWide, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return .none }
        let element = focused as! AXUIElement
        let frame = elementFrame(element)

        if let caret = caretRect(element, in: frame) { return .caret(anchor(caret, in: frame)) }
        // Chromium/Electron often report bogus caret bounds: anchor on a small focused text field instead.
        if let frame, !frame.isEmpty, frame.height >= 1, frame.height <= 120, frame.width >= 1,
           isTextInput(element) {
            return .field(frame)
        }
        return .none
    }

    /// In a small field (e.g. Safari's address bar) the caret is shorter than the field, so a panel
    /// placed under the caret would cover the field: stretch it to the field's height, keeping its x.
    /// Large text views keep the caret line.
    nonisolated static func anchor(_ caret: CGRect, in field: CGRect?) -> CGRect {
        guard let field, !field.isEmpty, field.height <= 120 else { return caret }
        return CGRect(x: caret.minX, y: field.minY, width: caret.width, height: field.height)
    }

    private nonisolated static func isTextInput(_ element: AXUIElement) -> Bool {
        guard let role = attribute(element, kAXRoleAttribute) as? String else { return false }
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
    }

    /// False for bounds that cannot be a caret: null/infinite, huge, or (when the focused
    /// element's frame is known) away from that element. Chromium-based apps return `.success`
    /// with such rects (e.g. x≈0 or the wrong coordinate space). Zero height is allowed.
    nonisolated static func isPlausibleCaret(_ caret: CGRect, in element: CGRect?) -> Bool {
        guard !caret.isNull, !caret.isInfinite,
              caret.height >= 0, caret.height <= 200, caret.width <= 400,
              // Chromium's bogus bounds sit at global x = 0; a maximised window would contain them.
              abs(caret.minX) >= 1
        else { return false }
        if let element, !element.isEmpty {
            return element.insetBy(dx: -24, dy: -24).contains(CGPoint(x: caret.midX, y: caret.midY))
        }
        return true
    }

    /// Plausible caret bounds of the selection in `element`, or nil.
    private nonisolated static func caretRect(_ element: AXUIElement, in frame: CGRect?) -> CGRect? {
        guard let rangeRef = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        let rangeValue = rangeRef as! AXValue
        var range = CFRange()
        guard AXValueGetType(rangeValue) == .cfRange,
              AXValueGetValue(rangeValue, .cfRange, &range)
        else { return nil }

        // A selection anchors on its first character (its union rect can be wide or multi-line).
        var anchor = range.length > 0 ? CFRange(location: range.location, length: 1) : range
        let anchorValue = range.length > 0 ? AXValueCreate(.cfRange, &anchor) : rangeValue
        let primary = anchorValue.flatMap { bounds(element, $0) }.flatMap {
            isPlausibleCaret($0, in: frame) ? $0 : nil
        }
        if let primary, primary.height > 0 { return primary }
        if range.length == 0, range.location > 0 {
            // Empty selection often reports zero-height bounds: use the previous character's.
            var previous = CFRange(location: range.location - 1, length: 1)
            if let previousValue = AXValueCreate(.cfRange, &previous),
               let rect = bounds(element, previousValue) {
                let caret = CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height)
                if isPlausibleCaret(caret, in: frame) { return caret }
            }
        }
        // Zero-height but otherwise plausible (e.g. caret at position 0): still better than the mouse.
        return primary
    }

    /// Frame of `element` (`kAXPositionAttribute` + `kAXSizeAttribute`), or nil.
    private nonisolated static func elementFrame(_ element: AXUIElement) -> CGRect? {
        guard let positionRef = attribute(element, kAXPositionAttribute),
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              let sizeRef = attribute(element, kAXSizeAttribute),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        let positionValue = positionRef as! AXValue
        let sizeValue = sizeRef as! AXValue
        guard AXValueGetType(positionValue) == .cgPoint,
              AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
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
