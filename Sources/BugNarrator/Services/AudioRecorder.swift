import AVFAudio
import AVFoundation
import Foundation
@MainActor
final class AudioRecorder: NSObject, @preconcurrency AVAudioRecorderDelegate, AudioRecording {
    private let recordingLogger = DiagnosticsLogger(category: .recording)
    private let permissionAccess: any MicrophonePermissionAccessing
    private let recoveryDirectoryURL: URL
    private let captureFormat: AudioRecorderCaptureFormat
    private let finalizationTimeoutNanoseconds: UInt64
    private let makeRecorder: AudioRecorderEngineFactory

    private var recorder: (any AudioRecorderEngine)?
    private var currentFileURL: URL?
    private var stopContinuation: CheckedContinuation<RecordedAudio, Error>?
    private var cancelContinuation: CheckedContinuation<Void, Never>?
    private var pendingStopResult: RecordedAudio?
    private var isCancelling = false
    private var finalizationTimeoutTask: Task<Void, Never>?

    init(
        recoveryDirectoryURL: URL = AppSupportLocation.appDirectory()
            .appendingPathComponent("RecoveredRecordings", isDirectory: true),
        captureFormat: AudioRecorderCaptureFormat = .aacM4A,
        finalizationTimeoutNanoseconds: UInt64 = 10_000_000_000,
        makeRecorder: @escaping AudioRecorderEngineFactory = { url, settings in
            try AVAudioRecorder(url: url, settings: settings)
        }
    ) {
        self.permissionAccess = SystemMicrophonePermissionAccess()
        self.recoveryDirectoryURL = recoveryDirectoryURL
        self.captureFormat = captureFormat
        self.finalizationTimeoutNanoseconds = finalizationTimeoutNanoseconds
        self.makeRecorder = makeRecorder
    }

    init(
        permissionAccess: any MicrophonePermissionAccessing,
        recoveryDirectoryURL: URL = AppSupportLocation.appDirectory()
            .appendingPathComponent("RecoveredRecordings", isDirectory: true),
        captureFormat: AudioRecorderCaptureFormat = .aacM4A,
        finalizationTimeoutNanoseconds: UInt64 = 10_000_000_000,
        makeRecorder: @escaping AudioRecorderEngineFactory = { url, settings in
            try AVAudioRecorder(url: url, settings: settings)
        }
    ) {
        self.permissionAccess = permissionAccess
        self.recoveryDirectoryURL = recoveryDirectoryURL
        self.captureFormat = captureFormat
        self.finalizationTimeoutNanoseconds = finalizationTimeoutNanoseconds
        self.makeRecorder = makeRecorder
    }

    var currentDuration: TimeInterval {
        recorder?.currentTime ?? 0
    }

    func validateRecordingPrerequisites() async -> AppError? {
        guard recorder == nil, stopContinuation == nil, cancelContinuation == nil else {
            return .recordingFailure("A recording session is already active.")
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-Preflight-\(UUID().uuidString)")
            .appendingPathExtension(captureFormat.fileExtension)

        do {
            let recorder = try makeRecorder(fileURL, recordingSettings)
            let prepared = recorder.prepareToRecord()
            try? FileManager.default.removeItem(at: fileURL)

            guard prepared else {
                return .microphoneUnavailable("Check that an input device is connected and available, then try again.")
            }

            return nil
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return .microphoneUnavailable("Check that an input device is connected and available, then try again. \(error.localizedDescription)")
        }
    }

    func validateRecordingActivation() async -> AppError? {
        guard recorder == nil, stopContinuation == nil, cancelContinuation == nil else {
            return .recordingFailure("A recording session is already active.")
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-ActivationProbe-\(UUID().uuidString)")
            .appendingPathExtension(captureFormat.fileExtension)

        do {
            let recorder = try makeRecorder(fileURL, recordingSettings)
            guard recorder.prepareToRecord() else {
                return resolvedMicrophoneAccessError(
                    defaultMessage: "Check that an input device is connected and available, then try again."
                )
            }

            guard recorder.record() else {
                return resolvedMicrophoneAccessError(
                    defaultMessage: "Check that an input device is connected and available, then try again."
                )
            }

            recorder.stop()
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        } catch {
            try? FileManager.default.removeItem(at: fileURL)

            if let permissionError = permissionBlockedError {
                return permissionError
            }

            return .microphoneUnavailable(
                "Check that an input device is connected and available, then try again. \(error.localizedDescription)"
            )
        }
    }

    func startRecording() async throws {
        recordingLogger.info("recording_start_requested", "A recording session start was requested.")

        guard recorder == nil, stopContinuation == nil, cancelContinuation == nil else {
            recordingLogger.warning("recording_start_rejected", "The recorder rejected a duplicate start request.")
            throw AppError.recordingFailure("A recording session is already active.")
        }

        if let prerequisiteError = await validateRecordingPrerequisites() {
            throw prerequisiteError
        }

        let fileURL = makeRecoverableRecordingURL()

        do {
            try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
            let recorder = try makeRecorder(fileURL, recordingSettings)
            recorder.delegate = self
            guard recorder.prepareToRecord() else {
                throw resolvedMicrophoneAccessError(
                    defaultMessage: "Check that an input device is connected and available, then try again."
                )
            }

            guard recorder.record() else {
                throw resolvedMicrophoneAccessError(
                    defaultMessage: "Check that an input device is connected and available, then try again."
                )
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
            try? FileManager.default.removeItem(at: fileURL)
            recordingLogger.error("recording_start_failed", error.userMessage)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
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
            scheduleStopTimeout(fileName: currentFileURL.lastPathComponent)
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
            scheduleCancelTimeout(fileName: currentFileURL.lastPathComponent)
            recorder.stop()
        }

        if !preserveFile {
            await Self.removeItemIfPresent(at: fileURL)
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.handleRecordingFinished(successfully: flag)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        Task { @MainActor [weak self] in
            self?.handleEncoderError(error)
        }
    }

    private func handleRecordingFinished(successfully flag: Bool) {
        let stopContinuation = self.stopContinuation
        let cancelContinuation = self.cancelContinuation
        let pendingStopResult = self.pendingStopResult
        let isCancelling = self.isCancelling

        cleanup()

        if isCancelling {
            recordingLogger.info("recording_cancelled", "The active recording session was cancelled.")
            cancelContinuation?.resume()
            // If a stop was in flight when cancel was requested, unblock the
            // stopRecording caller so it doesn't hang forever.
            stopContinuation?.resume(throwing: AppError.recordingFailure("The recording was cancelled."))
            return
        }

        guard flag, let pendingStopResult else {
            recordingLogger.error("recording_finalize_failed", "The recorded audio file could not be finalized.")
            stopContinuation?.resume(throwing: AppError.recordingFailure("The recorded audio file could not be finalized."))
            return
        }

        Task { [recordingLogger] in
            do {
                try await Self.validateRecordedAudioFile(at: pendingStopResult.fileURL)
            } catch {
                recordingLogger.error(
                    "recording_validation_failed",
                    (error as? AppError)?.userMessage ?? error.localizedDescription
                )
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
    }

    private func handleEncoderError(_ error: (any Error)?) {
        let stopContinuation = self.stopContinuation
        let cancelContinuation = self.cancelContinuation
        let isCancelling = self.isCancelling

        cleanup()

        if isCancelling {
            recordingLogger.info("recording_cancelled", "The active recording session was cancelled during encoder shutdown.")
            cancelContinuation?.resume()
            stopContinuation?.resume(throwing: AppError.recordingFailure("The recording was cancelled."))
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
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        recorder?.delegate = nil
        recorder = nil
        currentFileURL = nil
        stopContinuation = nil
        cancelContinuation = nil
        pendingStopResult = nil
        isCancelling = false
    }

    private func scheduleStopTimeout(fileName: String) {
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: finalizationTimeoutNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            // Capture and nil-swap the continuation atomically so the delegate
            // callback cannot also resume it if it fires on the next run-loop tick.
            guard let continuation = self.stopContinuation else { return }
            self.stopContinuation = nil

            recordingLogger.error(
                "recording_finalize_timeout",
                "The recorded audio file did not finish finalizing before the timeout.",
                metadata: ["file_name": fileName]
            )
            cleanup()
            continuation.resume(
                throwing: AppError.recordingFailure("The recorded audio file did not finish finalizing before the timeout.")
            )
        }
    }

    private func scheduleCancelTimeout(fileName: String) {
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: finalizationTimeoutNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            guard let continuation = self.cancelContinuation else { return }
            self.cancelContinuation = nil

            recordingLogger.warning(
                "recording_cancel_timeout",
                "Audio recording cancellation did not receive a final delegate callback before the timeout.",
                metadata: ["file_name": fileName]
            )
            cleanup()
            continuation.resume()
        }
    }

    private static func removeItemIfPresent(at url: URL) async {
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }.value
    }

    private static func validateRecordedAudioFile(at url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try validateRecordedAudioFileSynchronously(at: url)
        }.value
    }

    private nonisolated static func validateRecordedAudioFileSynchronously(at url: URL) throws {
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

        do {
            let audioFile = try AVAudioFile(forReading: url)
            guard audioFile.fileFormat.sampleRate > 0, audioFile.length > 0 else {
                throw AppError.recordingFailure("The recorded audio file did not contain playable audio.")
            }
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.recordingFailure("The recorded audio file could not be read.")
        }
    }

    private var permissionBlockedError: AppError? {
        switch permissionAccess.currentPermissionState() {
        case .denied:
            return .microphonePermissionDenied
        case .restricted:
            return .microphonePermissionRestricted
        case .authorized, .notDetermined:
            return nil
        }
    }

    private func resolvedMicrophoneAccessError(defaultMessage: String) -> AppError {
        permissionBlockedError ?? .microphoneUnavailable(defaultMessage)
    }

    private func makeRecoverableRecordingURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        return recoveryDirectoryURL
            .appendingPathComponent("\(timestamp)-recording-\(UUID().uuidString)")
            .appendingPathExtension(captureFormat.fileExtension)
    }

    private var recordingSettings: [String: Any] {
        captureFormat.recordingSettings
    }
}
