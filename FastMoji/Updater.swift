import AppKit
import Sparkle

/// Sparkle updater, started only when `SUPublicEDKey` is set (an empty key would show a misconfiguration alert).
/// While the menubar item shows, a background check (at launch, then every `SUScheduledCheckInterval`) that finds an
/// update shows no Sparkle dialog (gentle reminders): it sets `availableUpdateVersion`, which badges the menubar icon
/// and shows "Update to FastMoji <version>…" in the popover. With the menubar off, Sparkle shows its dialog.
@MainActor
@Observable
final class Updater: NSObject {
    private(set) var canCheck = false
    /// Version of the update a background check found, until its update session ends.
    private(set) var availableUpdateVersion: String?
    var updateAvailable: Bool { availableUpdateVersion != nil }

    @ObservationIgnored private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
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

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// The menubar badge stands in for Sparkle's dialog on background checks; with the menubar off, the badge would
    /// have nowhere to go, so Sparkle shows its dialog.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        !AppSettings.menubarEnabled
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        availableUpdateVersion = update.displayVersionString
    }

    /// Clears the badge after install, skip, "Remind Me Later" or an error.
    func standardUserDriverWillFinishUpdateSession() {
        if availableUpdateVersion != nil { availableUpdateVersion = nil }
    }
}
