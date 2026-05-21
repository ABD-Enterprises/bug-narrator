import Foundation

enum AppUtilityActionResult: Equatable {
    case opened
    case failed(message: String)
}

@MainActor
final class AppUtilityActionController {
    var showTranscriptWindow: (() -> Void)?
    var showSettingsWindow: (() -> Void)?
    var showAboutWindow: (() -> Void)?
    var showChangelogWindow: (() -> Void)?
    var showSupportWindow: (() -> Void)?
    var showRecordingControlWindow: (() -> Void)?

    private let urlHandler: any URLOpening
    private let permissionRecoveryController: PermissionRecoveryController
    private let settingsLogger = DiagnosticsLogger(category: .settings)

    init(
        urlHandler: any URLOpening,
        permissionRecoveryController: PermissionRecoveryController
    ) {
        self.urlHandler = urlHandler
        self.permissionRecoveryController = permissionRecoveryController
    }

    func openTranscriptHistory() {
        showTranscriptWindow?()
    }

    func openRecordingControls() {
        showRecordingControlWindow?()
    }

    func openSettings() {
        settingsLogger.debug("open_settings", "Opening the Settings window.")
        showSettingsWindow?()
    }

    func openAbout() {
        showAboutWindow?()
    }

    func openChangelog() {
        showChangelogWindow?()
    }

    func openGitHubRepository() -> AppUtilityActionResult {
        openExternalURL(BugNarratorLinks.repository, label: "GitHub repository")
    }

    func openDocumentation() -> AppUtilityActionResult {
        openExternalURL(BugNarratorLinks.documentation, label: "documentation")
    }

    func openIssueReporter() -> AppUtilityActionResult {
        openExternalURL(BugNarratorLinks.issues, label: "issue tracker")
    }

    func openSupportDevelopment() {
        showSupportWindow?()
    }

    func openSupportDonationPage() -> AppUtilityActionResult {
        openExternalURL(BugNarratorLinks.supportDevelopment, label: "PayPal donation page")
    }

    func openMicrophonePrivacySettings() -> PermissionSettingsOpenResult {
        permissionRecoveryController.openMicrophonePrivacySettings()
    }

    func openScreenRecordingPrivacySettings() -> PermissionSettingsOpenResult {
        permissionRecoveryController.openScreenRecordingPrivacySettings()
    }

    func openSystemAudioPrivacySettings() -> PermissionSettingsOpenResult {
        permissionRecoveryController.openSystemAudioPrivacySettings()
    }

    func checkForUpdates() -> AppUtilityActionResult {
        openExternalURL(BugNarratorLinks.releases, label: "releases page")
    }

    private func openExternalURL(_ url: URL, label: String) -> AppUtilityActionResult {
        guard urlHandler.open(url) else {
            return .failed(message: "BugNarrator could not open the \(label).")
        }

        settingsLogger.info(
            "external_link_opened",
            "Opened an external support or documentation link.",
            metadata: ["label": label]
        )
        return .opened
    }
}
