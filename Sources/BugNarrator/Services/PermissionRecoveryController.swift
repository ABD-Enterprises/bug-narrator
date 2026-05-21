import Foundation

enum PermissionRecoveryRefreshOutcome: Equatable {
    case unchanged
    case recovered(AppStatus)
}

enum PermissionSettingsOpenResult: Equatable {
    case opened(URL)
    case failed(String)
}

@MainActor
final class PermissionRecoveryStatusPresenter {
    private let errorPresenter: AppErrorPresenter

    init(errorPresenter: AppErrorPresenter) {
        self.errorPresenter = errorPresenter
    }

    func present(_ outcome: PermissionRecoveryRefreshOutcome) {
        guard case .recovered(let status) = outcome else {
            return
        }

        errorPresenter.setStatus(status)
    }
}

@MainActor
final class PermissionRecoveryController {
    private let microphonePermissionService: any MicrophonePermissionServicing
    private let screenCapturePermissionService: any ScreenCapturePermissionServicing
    private let urlHandler: any URLOpening
    private let runtimeEnvironment: AppRuntimeEnvironment
    private let permissionsLogger = DiagnosticsLogger(category: .permissions)

    init(
        microphonePermissionService: any MicrophonePermissionServicing,
        screenCapturePermissionService: any ScreenCapturePermissionServicing,
        urlHandler: any URLOpening,
        runtimeEnvironment: AppRuntimeEnvironment
    ) {
        self.microphonePermissionService = microphonePermissionService
        self.screenCapturePermissionService = screenCapturePermissionService
        self.urlHandler = urlHandler
        self.runtimeEnvironment = runtimeEnvironment
    }

    func refreshRecoveryState(
        currentError: AppError?,
        statusPhase: AppStatus.Phase
    ) -> PermissionRecoveryRefreshOutcome {
        permissionsLogger.debug(
            "permission_recovery_refresh_started",
            "Refreshing permission recovery state after BugNarrator became active.",
            metadata: [
                "microphone_status": microphonePermissionService.currentStatus().rawValue,
                "screen_capture_status": screenCapturePermissionService.currentStatus().rawValue
            ]
        )

        switch currentError {
        case .microphonePermissionDenied?, .microphonePermissionRestricted?, .microphoneUnavailable?:
            guard statusPhase != .recording, statusPhase != .transcribing else {
                return .unchanged
            }

            guard microphonePermissionService.currentStatus() == .granted else {
                return .unchanged
            }

            return .recovered(.idle("Microphone access enabled. You can start recording again."))
        case .screenRecordingPermissionDenied?:
            guard screenCapturePermissionService.currentStatus() == .granted else {
                return .unchanged
            }

            if statusPhase == .recording {
                return .recovered(.recording("Screen Recording access enabled. You can capture screenshots again."))
            }

            return .recovered(.idle("Screen Recording access enabled. You can capture screenshots again."))
        default:
            return .unchanged
        }
    }

    func microphoneRecoveryGuidance(currentError: AppError?) -> MicrophoneRecoveryGuidance {
        microphonePermissionService.recoveryGuidance(
            for: microphoneRecoveryStatus(currentError: currentError),
            runtimeEnvironment: runtimeEnvironment
        )
    }

    func openMicrophonePrivacySettings() -> PermissionSettingsOpenResult {
        openPrivacySettings(
            candidateURLs: [
                BugNarratorLinks.microphonePrivacySettings,
                BugNarratorLinks.securityPrivacySettings,
                BugNarratorLinks.systemSettingsApp
            ],
            failureMessage: "BugNarrator could not open Microphone settings automatically."
        )
    }

    func openScreenRecordingPrivacySettings() -> PermissionSettingsOpenResult {
        openPrivacySettings(
            candidateURLs: [
                BugNarratorLinks.screenRecordingPrivacySettings,
                BugNarratorLinks.securityPrivacySettings,
                BugNarratorLinks.systemSettingsApp
            ],
            failureMessage: "BugNarrator could not open Screen Recording settings automatically."
        )
    }

    func openSystemAudioPrivacySettings() -> PermissionSettingsOpenResult {
        openPrivacySettings(
            candidateURLs: [
                BugNarratorLinks.screenRecordingPrivacySettings,
                BugNarratorLinks.securityPrivacySettings,
                BugNarratorLinks.systemSettingsApp
            ],
            failureMessage: "BugNarrator could not open Screen & System Audio Recording settings automatically."
        )
    }

    func validateRuntimeConfiguration() {
        guard let microphoneUsageDescription = Bundle.main.object(
            forInfoDictionaryKey: "NSMicrophoneUsageDescription"
        ) as? String else {
            permissionsLogger.error(
                "runtime_configuration_missing_microphone_usage_description",
                "BugNarrator is missing NSMicrophoneUsageDescription. macOS microphone prompting will not work correctly."
            )
            return
        }

        if microphoneUsageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            permissionsLogger.error(
                "runtime_configuration_empty_microphone_usage_description",
                "BugNarrator has an empty NSMicrophoneUsageDescription. macOS microphone prompting will not work correctly."
            )
        }
    }

    func logLaunchPermissionSnapshot() {
        permissionsLogger.info(
            "launch_permission_snapshot",
            "Captured the initial permission state snapshot for this BugNarrator app copy.",
            metadata: [
                "bundle_path": runtimeEnvironment.bundlePath,
                "is_local_testing_build": runtimeEnvironment.isLocalTestingBuild ? "yes" : "no",
                "microphone_status": microphonePermissionService.currentStatus().rawValue,
                "screen_capture_status": screenCapturePermissionService.currentStatus().rawValue
            ]
        )
    }

    private func openPrivacySettings(
        candidateURLs: [URL],
        failureMessage: String
    ) -> PermissionSettingsOpenResult {
        for url in candidateURLs where urlHandler.open(url) {
            return .opened(url)
        }

        return .failed(failureMessage)
    }

    private func microphoneRecoveryStatus(currentError: AppError?) -> MicrophonePermissionStatus {
        switch currentError {
        case .microphonePermissionDenied:
            return .denied
        case .microphonePermissionRestricted:
            return .restricted
        case .microphoneUnavailable:
            return .captureSetupFailed
        default:
            return microphonePermissionService.currentStatus()
        }
    }
}
