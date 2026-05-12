import Foundation

@MainActor
final class RoutingAudioRecorder: AudioRecording {
    private let settingsStore: SettingsStore
    private let microphoneRecorder: any AudioRecording
    private let systemAudioRecorder: any AudioRecording
    private let microphoneAndSystemAudioRecorder: any AudioRecording

    private var activeRecorder: (any AudioRecording)?

    init(
        settingsStore: SettingsStore,
        microphoneRecorder: any AudioRecording = AudioRecorder(),
        systemAudioRecorder: any AudioRecording = SystemAudioRecorder(),
        microphoneAndSystemAudioRecorder: (any AudioRecording)? = nil
    ) {
        self.settingsStore = settingsStore
        self.microphoneRecorder = microphoneRecorder
        self.systemAudioRecorder = systemAudioRecorder
        self.microphoneAndSystemAudioRecorder = microphoneAndSystemAudioRecorder ?? MixedAudioRecorder(
            microphoneRecorder: AudioRecorder(),
            systemAudioRecorder: SystemAudioRecorder()
        )
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

        guard settingsStore.systemAudioCaptureEnabled else {
            return .systemAudioFeatureDisabled
        }

        guard settingsStore.hasAcceptedSystemAudioRecordingConsent else {
            return .systemAudioConsentRequired
        }

        return nil
    }
}
