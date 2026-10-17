import AppKit
import Carbon.HIToolbox
import Observation

/// Secure Input state. While it is on (a password field, Terminal > Secure Keyboard Entry),
/// CGEventTaps receive no key events, so typing triggers silently stop working.
/// Polled every 2 s while running: no notification exists for it.
/// Never read from the event-tap callback.
/// No app name: the session dictionary's `kCGSSessionSecureInputPID` names the frontmost app,
/// not the process holding Secure Input.
@MainActor
@Observable
final class SecureInputMonitor {
    private(set) var isOn = false
    /// Called on every change of `isOn` found by the polling (not by `stop()`).
    @ObservationIgnored var onChange: ((Bool) -> Void)?

    @ObservationIgnored private var timer: Timer?

    private static let interval: TimeInterval = 2

    /// Reads the state now, then every 2 s. Idempotent.
    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                self.refresh()
            }
        }
        // `.common`: keep polling while a menu or the popover tracks events.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops polling and clears the state (nothing is known without the tap).
    func stop() {
        timer?.invalidate()
        timer = nil
        if isOn { isOn = false }
    }

    /// Assigns only on change, so SwiftUI is not invalidated every 2 s.
    private func refresh() {
        let on = IsSecureEventInputEnabled()
        guard on != isOn else { return }
        isOn = on
        onChange?(on)
    }
}
