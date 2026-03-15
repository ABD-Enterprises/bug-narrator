import AVFAudio
import AVFoundation
import Foundation

struct RecordedAudio {
    let fileURL: URL
    let duration: TimeInterval
}

@MainActor
final class AudioRecorder: NSObject, @preconcurrency AVAudioRecorderDelegate, AudioRecording {
    private let recordingLogger = DiagnosticsLogger(category: .recording)
    private let permissionsLogger = DiagnosticsLogger(category: .permissions)

    private var recorder: AVAudioRecorder?
    private var currentFileURL: URL?
    private var stopContinuation: CheckedContinuation<RecordedAudio, Error>?
    private var cancelContinuation: CheckedContinuation<Void, Never>?
    private var pendingStopResult: RecordedAudio?
    private var isCancelling = false

    var currentDuration: TimeInterval {
        recorder?.currentTime ?? 0
    }

    func microphonePermissionState() -> MicrophonePermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .authorized
        case .undetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .restricted
        }
    }

    func startRecording() async throws {
        recordingLogger.info("recording_start_requested", "A recording session start was requested.")

        guard recorder == nil, stopContinuation == nil, cancelContinuation == nil else {
            recordingLogger.warning("recording_start_rejected", "The recorder rejected a duplicate start request.")
            throw AppError.recordingFailure("A recording session is already active.")
        }

        guard await requestMicrophonePermissionIfNeeded() else {
            permissionsLogger.warning("microphone_permission_denied", "Microphone access was denied or restricted.")
            throw AppError.microphonePermissionDenied
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw AppError.recordingFailure("The recorder could not start.")
            }

            self.recorder = recorder
            self.currentFileURL = fileURL
            self.pendingStopResult = nil
            self.isCancelling = false
            recordingLogger.info(
                "recording_started",
                "Audio recording started successfully.",
                metadata: ["file_name": fileURL.lastPathComponent]
            )
        } catch let error as AppError {
            recordingLogger.error("recording_start_failed", error.userMessage)
            throw error
        } catch {
            recordingLogger.error("recording_start_failed", "Audio recording could not be started.")
            throw AppError.recordingFailure(error.localizedDescription)
        }
    }

    func stopRecording() async throws -> RecordedAudio {
        guard let recorder, let currentFileURL else {
            throw AppError.recordingFailure("There is no active recording.")
        }

        guard stopContinuation == nil else {
            recordingLogger.warning("recording_stop_rejected", "The recorder rejected a duplicate stop request.")
            throw AppError.recordingFailure("A stop request is already in progress.")
        }

        recordingLogger.info(
            "recording_stop_requested",
            "The current recording session is being finalized.",
            metadata: ["file_name": currentFileURL.lastPathComponent]
        )
        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            pendingStopResult = RecordedAudio(fileURL: currentFileURL, duration: recorder.currentTime)
            recorder.stop()
        }
    }

    func cancelRecording(preserveFile: Bool) async {
        guard let recorder, let currentFileURL else {
            cleanup()
            return
        }

        recordingLogger.info(
            "recording_cancel_requested",
            preserveFile
                ? "The active recording session is being cancelled and the temporary audio file will be preserved."
                : "The active recording session is being cancelled and the temporary audio file will be removed.",
            metadata: ["file_name": currentFileURL.lastPathComponent]
        )
        let fileURL = currentFileURL
        isCancelling = true

        await withCheckedContinuation { continuation in
            cancelContinuation = continuation
            recorder.stop()
        }

        if !preserveFile {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let stopContinuation = self.stopContinuation
        let cancelContinuation = self.cancelContinuation
        let pendingStopResult = self.pendingStopResult
        let isCancelling = self.isCancelling

        cleanup()

        if isCancelling {
            recordingLogger.info("recording_cancelled", "The active recording session was cancelled.")
            cancelContinuation?.resume()
            return
        }

        guard flag, let pendingStopResult else {
            recordingLogger.error("recording_finalize_failed", "The recorded audio file could not be finalized.")
            stopContinuation?.resume(throwing: AppError.recordingFailure("The recorded audio file could not be finalized."))
            return
        }

        do {
            try validateRecordedAudioFile(at: pendingStopResult.fileURL)
        } catch {
            recordingLogger.error("recording_validation_failed", (error as? AppError)?.userMessage ?? error.localizedDescription)
            stopContinuation?.resume(throwing: error)
            return
        }

        recordingLogger.info(
            "recording_stopped",
            "Audio recording finished successfully.",
            metadata: [
                "file_name": pendingStopResult.fileURL.lastPathComponent,
                "duration_seconds": String(format: "%.2f", pendingStopResult.duration)
            ]
        )
        stopContinuation?.resume(returning: pendingStopResult)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let stopContinuation = self.stopContinuation
        let cancelContinuation = self.cancelContinuation
        let isCancelling = self.isCancelling

        cleanup()

        if isCancelling {
            recordingLogger.info("recording_cancelled", "The active recording session was cancelled during encoder shutdown.")
            cancelContinuation?.resume()
            return
        }

        recordingLogger.error(
            "recording_encoder_error",
            error?.localizedDescription ?? "The audio encoder reported an unexpected failure."
        )
        stopContinuation?.resume(
            throwing: AppError.recordingFailure(
                error?.localizedDescription ?? "The audio encoder reported an unexpected failure."
            )
        )
    }

    private func cleanup() {
        recorder?.delegate = nil
        recorder = nil
        currentFileURL = nil
        stopContinuation = nil
        cancelContinuation = nil
        pendingStopResult = nil
        isCancelling = false
    }

    private func requestMicrophonePermissionIfNeeded() async -> Bool {
        switch microphonePermissionState() {
        case .authorized:
            permissionsLogger.debug("microphone_permission_authorized", "Microphone access is already authorized.")
            return true
        case .notDetermined:
            permissionsLogger.info("microphone_permission_requested", "Requesting microphone access from macOS.")
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            permissionsLogger.warning("microphone_permission_blocked", "Microphone access is denied or restricted.")
            return false
        }
    }

    private func validateRecordedAudioFile(at url: URL) throws {
        let attributes: [FileAttributeKey: Any]

        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw AppError.recordingFailure("The recorded audio file could not be found.")
        }

        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 0 else {
            throw AppError.recordingFailure("The recorded audio file was empty.")
        }
    }
}
