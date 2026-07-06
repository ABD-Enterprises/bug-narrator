import Foundation
import XCTest
@testable import BugNarrator

@MainActor
final class MockAudioRecorder: AudioRecording, MicrophonePermissionAccessing {
    enum ActivationProbeBehavior {
        case automatic
        case success
        case error(AppError)
    }

    var currentDuration: TimeInterval = 0
    var requiresMicrophonePermission = true
    var startCallCount = 0
    var stopCallCount = 0
    var cancelPreserveArguments: [Bool] = []
    var startError: Error?
    var stopResults: [Result<RecordedAudio, Error>] = []
    var suspendStop = false
    var permissionState: MicrophonePermissionState = .authorized
    var requestedPermissionStates: [MicrophonePermissionState] = []
    var prerequisiteError: AppError?
    var activationProbeBehavior: ActivationProbeBehavior = .automatic
    private(set) var permissionRequestCallCount = 0
    private(set) var activationProbeCallCount = 0

    private var stopContinuation: CheckedContinuation<RecordedAudio, Error>?

    func currentPermissionState() -> MicrophonePermissionState {
        permissionState
    }

    func requestPermissionIfNeeded() async -> MicrophonePermissionState {
        permissionRequestCallCount += 1

        if !requestedPermissionStates.isEmpty {
            permissionState = requestedPermissionStates.removeFirst()
        }

        return permissionState
    }

    func validateRecordingPrerequisites() async -> AppError? {
        prerequisiteError
    }

    func validateRecordingActivation() async -> AppError? {
        activationProbeCallCount += 1

        switch activationProbeBehavior {
        case .automatic:
            if let prerequisiteError {
                return prerequisiteError
            }

            switch permissionState {
            case .authorized, .notDetermined:
                return nil
            case .denied:
                return .microphonePermissionDenied
            case .restricted:
                return .microphonePermissionRestricted
            }
        case .success:
            return nil
        case .error(let error):
            return error
        }
    }

    func startRecording() async throws {
        startCallCount += 1

        if let startError {
            throw startError
        }
    }

    func stopRecording() async throws -> RecordedAudio {
        stopCallCount += 1

        if suspendStop {
            return try await withCheckedThrowingContinuation { continuation in
                stopContinuation = continuation
            }
        }

        guard !stopResults.isEmpty else {
            throw AppError.recordingFailure("No mock stop result was configured.")
        }

        return try stopResults.removeFirst().get()
    }

    func cancelRecording(preserveFile: Bool) async {
        cancelPreserveArguments.append(preserveFile)
    }

    func resumeStop(with result: Result<RecordedAudio, Error>) {
        let continuation = stopContinuation
        stopContinuation = nil
        suspendStop = false

        switch result {
        case .success(let recordedAudio):
            continuation?.resume(returning: recordedAudio)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}
