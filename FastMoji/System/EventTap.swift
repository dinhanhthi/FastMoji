import AppKit
import CoreGraphics

/// One active `CGEventTap` (keyDown + left/right mouse down) on the main run loop.
/// The handler is called synchronously on the main thread and decides whether the
/// event is swallowed (`true`) or passed through (`false`). Events posted by
/// `EmojiInserter` (tagged with `EmojiInserter.tag`) always pass through untouched.
///
/// The tap holds an unretained reference to `self`: the owner must call `stop()`
/// before releasing it.
@MainActor
final class EventTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((CGEventType, CGEvent) -> Bool)?

    var isRunning: Bool { tap != nil }

    private static let mask: CGEventMask =
        CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        | CGEventMask(1) << CGEventMask(CGEventType.leftMouseDown.rawValue)
        | CGEventMask(1) << CGEventMask(CGEventType.rightMouseDown.rawValue)

    /// Starts the tap (or just replaces the handler if it is already running).
    /// Returns false if the tap cannot be created, e.g. Accessibility is not granted.
    func start(handler: @escaping (CGEventType, CGEvent) -> Bool) -> Bool {
        self.handler = handler
        if isRunning { return true }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let swallow = MainActor.assumeIsolated {
                    Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
                }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            self.handler = nil
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.tap = port
        self.source = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        handler = nil
    }

    /// Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        default:
            break
        }
        if event.getIntegerValueField(.eventSourceUserData) == EmojiInserter.tag { return false }
        return handler?(type, event) ?? false
    }
}
