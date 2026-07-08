import Foundation

@MainActor
final class RoutingAudioRecorder: AudioRecording {
    private let settingsStore: SettingsStore
    private let microphoneRecorder: any AudioRecording
    private let systemAudioRecorder: any AudioRecording
    private let microphoneAndSystemAudioRecorder: any AudioRecording
    private let recordingLogger: DiagnosticsLogger

    private var activeRecorder: (any AudioRecording)?

    init(
        settingsStore: SettingsStore,
        microphoneRecorder: (any AudioRecording)? = nil,
        systemAudioRecorder: any AudioRecording = SystemAudioRecorder(),
        microphoneAndSystemAudioRecorder: (any AudioRecording)? = nil,
        recordingLogger: DiagnosticsLogger = DiagnosticsLogger(category: .recording)
    ) {
        self.settingsStore = settingsStore
        let microphoneRecorder = microphoneRecorder ?? AudioRecorder(
            captureFormat: settingsStore.debugMode ? .wavPCM : .aacM4A
        )
        self.microphoneRecorder = microphoneRecorder
        self.systemAudioRecorder = systemAudioRecorder
        self.microphoneAndSystemAudioRecorder = microphoneAndSystemAudioRecorder ?? MixedAudioRecorder(
            microphoneRecorder: microphoneRecorder,
            systemAudioRecorder: systemAudioRecorder
        )
        self.recordingLogger = recordingLogger
    }

    var currentDuration: TimeInterval {
        activeRecorder?.currentDuration ?? selectedRecorder.currentDuration
    }

    var requiresMicrophonePermission: Bool {
        settingsStore.recordingAudioSource.usesMicrophone
    }

    func validateRecordingPrerequisites() async -> AppError? {
        if let readinessError = validateSystemAudioReadiness() {
            return readinessError
        }

        return await selectedRecorder.validateRecordingPrerequisites()
    }

    func validateRecordingActivation() async -> AppError? {
        if let readinessError = validateSystemAudioReadiness() {
            return readinessError
        }

        return await selectedRecorder.validateRecordingActivation()
    }

    func startRecording() async throws {
        guard activeRecorder == nil else {
            throw AppError.recordingFailure("A recording session is already active.")
        }

        if let readinessError = validateSystemAudioReadiness() {
            throw readinessError
        }

        let recorder = selectedRecorder
        try await recorder.startRecording()
        activeRecorder = recorder
    }

    func stopRecording() async throws -> RecordedAudio {
        guard let activeRecorder else {
            throw AppError.recordingFailure("There is no active recording.")
        }

        defer {
            self.activeRecorder = nil
        }

        return try await activeRecorder.stopRecording()
    }

    func cancelRecording(preserveFile: Bool) async {
        guard let activeRecorder else {
            return
        }

        self.activeRecorder = nil
        await activeRecorder.cancelRecording(preserveFile: preserveFile)
    }

    private var selectedRecorder: any AudioRecording {
        switch settingsStore.recordingAudioSource {
        case .microphone:
            return microphoneRecorder
        case .systemAudio:
            return systemAudioRecorder
        case .microphoneAndSystemAudio:
            return microphoneAndSystemAudioRecorder
        }
    }

    private func validateSystemAudioReadiness() -> AppError? {
        guard settingsStore.recordingAudioSource.usesSystemAudio else {
            return nil
        }

        let source = String(describing: settingsStore.recordingAudioSource)

        guard settingsStore.systemAudioCaptureEnabled else {
            recordingLogger.warning(
                "system_audio_readiness_feature_disabled",
                "System audio recording rejected: the experimental \"System audio capture modes\" toggle in Settings is off.",
                metadata: ["source": source]
            )
            return .systemAudioFeatureDisabled
        }

        guard settingsStore.hasAcceptedSystemAudioRecordingConsent else {
            recordingLogger.warning(
                "system_audio_readiness_consent_required",
                "System audio recording rejected: the recording-notice consent toggle in Settings has not been ticked.",
                metadata: ["source": source]
            )
            return .systemAudioConsentRequired
        }

        return nil
    }
}
