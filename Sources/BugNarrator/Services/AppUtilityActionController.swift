import AppKit
import Foundation

enum AppUtilityActionResult: Equatable {
    case opened
    /// A result worth telling the user about that is not a failure — the
    /// update check needs to say "you are current" or "1.0.42 is available",
    /// and the presenter previously surfaced failures only (#961).
    case informed(message: String)
    case failed(message: String)
}

@MainActor
final class AppUtilityActionResultPresenter {
    private let statusPhase: () -> AppStatus.Phase
    private let setStatus: (AppStatus) -> Void
    private let logger: DiagnosticsLogger

    init(
        statusPhase: @escaping () -> AppStatus.Phase,
        setStatus: @escaping (AppStatus) -> Void,
        logger: DiagnosticsLogger = DiagnosticsLogger(category: .settings)
    ) {
        self.statusPhase = statusPhase
        self.setStatus = setStatus
        self.logger = logger
    }

    func present(_ result: AppUtilityActionResult) {
        switch result {
        case .opened:
            return
        case .informed(let message):
            logger.info("utility_action_informed", message)
            setStatus(.idle(message))
        case .failed(let message):
            presentFailure(message)
        }
    }

    func present(_ result: PermissionSettingsOpenResult) {
        guard case .failed(let message) = result else {
            return
        }

        presentFailure(message)
    }

    func presentFailure(_ message: String) {
        logger.warning("utility_action_failed", message)
        setStatus(Self.failureStatus(message: message, statusPhase: statusPhase()))
    }

    static func failureStatus(message: String, statusPhase: AppStatus.Phase) -> AppStatus {
        switch statusPhase {
        case .recording:
            return .recording("\(message) Recording is still active.")
        case .transcribing:
            return .transcribing("\(message) Background work is still in progress.")
        case .idle, .success, .error:
            return .error(message)
        }
    }
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

    /// Asks the public releases feed rather than sending the user to look.
    /// A failed check falls back to the old behavior — opening the releases
    /// page — so the button never becomes a dead end.
    /// Asks the public releases feed rather than sending the user to look.
    /// The URL decision is `ReleaseUpdateOutcome.urlToOpen`, so a failed check
    /// still opens the releases page and the button never dead-ends.
    func checkForUpdates(
        checker: ReleaseUpdateChecker = ReleaseUpdateChecker(),
        metadata: BugNarratorMetadata = BugNarratorMetadata()
    ) async -> AppUtilityActionResult {
        let outcome = await checker.check(currentVersion: metadata.version)

        guard let url = outcome.urlToOpen(fallback: BugNarratorLinks.releases) else {
            return .informed(message: outcome.userMessage)
        }

        if case .failed(let message) = openExternalURL(url, label: "release page") {
            return .failed(message: message)
        }

        return .informed(message: outcome.userMessage)
    }

    func openScreenshot(_ screenshot: SessionScreenshot) -> AppUtilityActionResult {
        guard FileManager.default.fileExists(atPath: screenshot.fileURL.path) else {
            return .failed(message: "The selected screenshot file is no longer available on this Mac.")
        }

        return revealInFinder(screenshot.fileURL)
    }

    func revealInFinder(_ url: URL) -> AppUtilityActionResult {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return .opened
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
