import AppKit
import Sparkle

/// Sparkle updater, started only when `SUPublicEDKey` is set (an empty key would show a misconfiguration alert).
/// Background checks (at launch, then every `SUScheduledCheckInterval`) never pop Sparkle's dialog: a found update
/// sets `updateAvailable`, which shows the update button in the menubar popover and in Settings.
@MainActor
@Observable
final class Updater: NSObject {
    private(set) var canCheck = false
    private(set) var updateAvailable = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    func start() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        controller.startUpdater()
        canCheck = true
        if controller.updater.automaticallyChecksForUpdates { controller.updater.checkForUpdatesInBackground() }
    }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}

extension Updater: SPUUpdaterDelegate {
    /// Also called when automatic updates download in the background without any dialog.
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateAvailable = true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        updateAvailable = false
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem,
                 state: SPUUserUpdateState) {
        if choice == .skip { updateAvailable = false }
    }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// The update button stands in for Sparkle's dialog on background checks.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    /// Required by Sparkle when the delegate shows scheduled updates; `didFindValidUpdate` already set the flag.
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {}
}
