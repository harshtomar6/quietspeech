import Foundation
import Observation
import Sparkle

@Observable
@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    @ObservationIgnored private(set) var controller: SPUStandardUpdaterController?
    private(set) var isUpdateAvailable = false
    private let defaults: UserDefaults
    private let currentBuild: String
    private static let reminderKey = "updateReminderForBuild"

    init(startingUpdater: Bool = true, defaults: UserDefaults = .standard,
         currentBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") {
        self.defaults = defaults
        self.currentBuild = currentBuild
        super.init()
        isUpdateAvailable = !currentBuild.isEmpty && defaults.string(forKey: Self.reminderKey) == currentBuild
        controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    // Sparkle brings an existing update/download/installation window into
    // focus when a gentle reminder is selected, or starts a manual check.
    func installUpdate() {
        checkForUpdates()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        setUpdateAvailable(true)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        setUpdateAvailable(false)
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {
        // Dismissing or beginning a download does not make the update go
        // away. An explicit Skip does. Reminders survive restarting this
        // build but do not carry into an installed new build.
        if choice == .skip { setUpdateAvailable(false) }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Background checks announce themselves in our menu bar. A user
        // choosing Install New Update still gets Sparkle's standard UI.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        setUpdateAvailable(true)
    }

    private func setUpdateAvailable(_ available: Bool) {
        isUpdateAvailable = available
        if available, !currentBuild.isEmpty {
            defaults.set(currentBuild, forKey: Self.reminderKey)
        } else {
            defaults.removeObject(forKey: Self.reminderKey)
        }
    }
}
