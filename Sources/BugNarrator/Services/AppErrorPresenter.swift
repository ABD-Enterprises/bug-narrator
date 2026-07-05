import Foundation

enum AppErrorOperation: String {
    case generic
    case recordingStart = "recording_start"
    case recordingStop = "recording_stop"
    case transcription
    case retryTranscription = "retry_transcription"
    case postTranscription = "post_transcription"
    case screenshotCapture = "screenshot_capture"
    case diagnosticsExport = "diagnostics_export"
    case privacyExport = "privacy_export"
    case export
    case sessionLibrary = "session_library"
    case issueExtraction = "issue_extraction"
}

struct AppErrorNormalization: Equatable {
    let appError: AppError
    let operation: AppErrorOperation
    let underlyingErrorDescription: String?
}

struct AppErrorPresentationResult: Equatable {
    let appError: AppError
    let shouldOpenSettingsWindow: Bool
}

@MainActor
final class TranscriptPersistenceFailurePresenter {
    private let errorPresenter: AppErrorPresenter
    private let showTranscriptWindow: () -> Void
    private let sessionLibraryLogger: DiagnosticsLogger

    init(
        errorPresenter: AppErrorPresenter,
        showTranscriptWindow: @escaping () -> Void,
        sessionLibraryLogger: DiagnosticsLogger = DiagnosticsLogger(category: .sessionLibrary)
    ) {
        self.errorPresenter = errorPresenter
        self.showTranscriptWindow = showTranscriptWindow
        self.sessionLibraryLogger = sessionLibraryLogger
    }

    func present(_ error: Error, sessionID: UUID) {
        let normalizedError = errorPresenter.normalizeError(
            error,
            operation: .sessionLibrary,
            fallback: { .storageFailure($0) }
        )
        let appError = normalizedError.appError
        errorPresenter.logAppError(normalizedError, context: "transcript_persist_failed")
        var metadata = errorPresenter.appErrorMetadata(for: normalizedError, context: "transcript_persist_failed")
        metadata["session_id"] = sessionID.uuidString
        sessionLibraryLogger.error(
            "transcript_persist_failed",
            "Transcription succeeded, but saving the transcript locally failed.",
            metadata: metadata
        )
        errorPresenter.setStatus(
            .error("Transcript ready, but \(appError.userMessage(for: errorPresenter.activeProvider))"),
            error: appError
        )
        showTranscriptWindow()
    }
}

@MainActor
final class PostTranscriptionFailurePresenter {
    private let errorPresenter: AppErrorPresenter
    private let showSettingsWindow: () -> Void

    init(
        errorPresenter: AppErrorPresenter,
        showSettingsWindow: @escaping () -> Void
    ) {
        self.errorPresenter = errorPresenter
        self.showSettingsWindow = showSettingsWindow
    }

    func present(
        _ error: Error,
        operation: AppErrorOperation = .postTranscription
    ) {
        let result = errorPresenter.presentPostTranscriptionError(error, operation: operation)
        if result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
    }
}

@MainActor
final class AppErrorPresenter {
    private let presentationState: AppPresentationState
    private let telemetryRecorder: any OperationalTelemetryRecording
    private let provider: () -> AIProvider
    private let recordingLogger = DiagnosticsLogger(category: .recording)
    private let transcriptionLogger = DiagnosticsLogger(category: .transcription)
    private let sessionLibraryLogger = DiagnosticsLogger(category: .sessionLibrary)
    private let exportLogger = DiagnosticsLogger(category: .export)
    private let permissionsLogger = DiagnosticsLogger(category: .permissions)
    private let screenshotLogger = DiagnosticsLogger(category: .screenshots)
    private let settingsLogger = DiagnosticsLogger(category: .settings)

    init(
        presentationState: AppPresentationState,
        telemetryRecorder: any OperationalTelemetryRecording,
        provider: @escaping () -> AIProvider = { .openAI }
    ) {
        self.presentationState = presentationState
        self.telemetryRecorder = telemetryRecorder
        self.provider = provider
    }

    var activeProvider: AIProvider {
        provider()
    }

    func setStatus(_ status: AppStatus, error: AppError? = nil) {
        presentationState.setStatus(status, error: error)
    }

    func presentError(
        _ error: Error,
        operation: AppErrorOperation = .generic,
        fallback: (String) -> AppError = { .transcriptionFailure($0) }
    ) -> AppErrorPresentationResult {
        let normalizedError = normalizeError(error, operation: operation, fallback: fallback)
        let appError = normalizedError.appError
        let currentProvider = provider()
        logAppError(normalizedError, context: "present_error")
        setStatus(.error(appError.userMessage(for: currentProvider)), error: appError)
        return AppErrorPresentationResult(
            appError: appError,
            shouldOpenSettingsWindow: shouldOpenSettingsWindowAfterPresenting(appError)
        )
    }

    func presentPostTranscriptionError(
        _ error: Error,
        operation: AppErrorOperation = .postTranscription
    ) -> AppErrorPresentationResult {
        let normalizedError = normalizeError(
            error,
            operation: operation,
            fallback: { .issueExtractionFailure($0) }
        )
        let appError = normalizedError.appError
        let currentProvider = provider()
        logAppError(normalizedError, context: "present_post_transcription_error")
        setStatus(
            .error("Transcript ready, but \(appError.userMessage(for: currentProvider))"),
            error: appError
        )
        return AppErrorPresentationResult(
            appError: appError,
            shouldOpenSettingsWindow: appError.suggestsProviderSettings(for: currentProvider)
        )
    }

    func normalizeError(
        _ error: Error,
        operation: AppErrorOperation,
        fallback: (String) -> AppError
    ) -> AppErrorNormalization {
        if let appError = error as? AppError {
            return AppErrorNormalization(
                appError: appError,
                operation: operation,
                underlyingErrorDescription: nil
            )
        }

        let underlyingDescription = error.localizedDescription
        return AppErrorNormalization(
            appError: fallback(underlyingDescription),
            operation: operation,
            underlyingErrorDescription: underlyingDescription
        )
    }

    func logAppError(
        _ error: AppError,
        context: String,
        operation: AppErrorOperation = .generic
    ) {
        logAppError(
            AppErrorNormalization(
                appError: error,
                operation: operation,
                underlyingErrorDescription: nil
            ),
            context: context
        )
    }

    func logAppError(_ normalizedError: AppErrorNormalization, context: String) {
        let error = normalizedError.appError
        let metadata = appErrorMetadata(for: normalizedError, context: context)
        let message = error.userMessage(for: provider())

        telemetryRecorder.record(.appError, metadata: metadata)

        switch error {
        case .microphonePermissionDenied,
             .microphonePermissionRestricted,
             .microphoneUnavailable,
             .systemAudioFeatureDisabled,
             .systemAudioConsentRequired,
             .systemAudioUnavailable,
             .screenRecordingPermissionDenied:
            permissionsLogger.warning(.appError, message, metadata: metadata)
        case .missingAPIKey, .invalidAPIKey, .revokedAPIKey:
            settingsLogger.warning(.appError, message, metadata: metadata)
        case .recordingFailure:
            recordingLogger.error(.appError, message, metadata: metadata)
        case .transcriptionFailure, .openAIRequestRejected, .issueExtractionFailure, .emptyTranscript, .networkTimeout, .networkFailure, .rateLimited:
            transcriptionLogger.error(.appError, message, metadata: metadata)
        case .screenshotCaptureFailure:
            screenshotLogger.error(.appError, message, metadata: metadata)
        case .exportConfigurationMissing, .exportFailure:
            exportLogger.error(.appError, message, metadata: metadata)
        case .storageFailure:
            sessionLibraryLogger.error(.appError, message, metadata: metadata)
        case .noActiveSession:
            recordingLogger.warning(.appError, message, metadata: metadata)
        case .diagnosticsFailure:
            settingsLogger.error(.appError, message, metadata: metadata)
        }
    }

    func appErrorMetadata(
        for normalizedError: AppErrorNormalization,
        context: String
    ) -> [String: String] {
        var metadata = [
            "context": context,
            "operation": normalizedError.operation.rawValue,
            "error_type": telemetryErrorType(for: normalizedError.appError)
        ]

        if let underlyingErrorDescription = normalizedError.underlyingErrorDescription {
            metadata["underlying_error"] = underlyingErrorDescription
        }

        return metadata
    }

    private func shouldOpenSettingsWindowAfterPresenting(_ error: AppError) -> Bool {
        switch error {
        case .missingAPIKey, .invalidAPIKey, .revokedAPIKey, .exportConfigurationMissing:
            return true
        default:
            return false
        }
    }

    private func telemetryErrorType(for error: AppError) -> String {
        switch error {
        case .microphonePermissionDenied:
            return "microphone_permission_denied"
        case .microphonePermissionRestricted:
            return "microphone_permission_restricted"
        case .microphoneUnavailable:
            return "microphone_unavailable"
        case .systemAudioFeatureDisabled:
            return "system_audio_feature_disabled"
        case .systemAudioConsentRequired:
            return "system_audio_consent_required"
        case .systemAudioUnavailable:
            return "system_audio_unavailable"
        case .screenRecordingPermissionDenied:
            return "screen_recording_permission_denied"
        case .missingAPIKey:
            return "missing_api_key"
        case .invalidAPIKey:
            return "invalid_api_key"
        case .revokedAPIKey:
            return "revoked_api_key"
        case .recordingFailure:
            return "recording_failure"
        case .transcriptionFailure:
            return "transcription_failure"
        case .openAIRequestRejected:
            return "openai_request_rejected"
        case .issueExtractionFailure:
            return "issue_extraction_failure"
        case .emptyTranscript:
            return "empty_transcript"
        case .networkTimeout:
            return "network_timeout"
        case .networkFailure:
            return "network_failure"
        case .rateLimited:
            return "rate_limited"
        case .screenshotCaptureFailure:
            return "screenshot_capture_failure"
        case .exportConfigurationMissing:
            return "export_configuration_missing"
        case .exportFailure:
            return "export_failure"
        case .storageFailure:
            return "storage_failure"
        case .noActiveSession:
            return "no_active_session"
        case .diagnosticsFailure:
            return "diagnostics_failure"
        }
    }
}
