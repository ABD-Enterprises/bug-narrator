@preconcurrency import AVFoundation
import Foundation

@MainActor
final class MixedAudioRecorder: AudioRecording {
    private let recordingLogger = DiagnosticsLogger(category: .recording)
    private let microphoneRecorder: any AudioRecording
    private let systemAudioRecorder: any AudioRecording
    private let outputDirectoryURL: URL

    private var isRecording = false

    init(
        microphoneRecorder: any AudioRecording,
        systemAudioRecorder: any AudioRecording,
        outputDirectoryURL: URL = AppSupportLocation.appDirectory()
            .appendingPathComponent("RecoveredRecordings", isDirectory: true)
    ) {
        self.microphoneRecorder = microphoneRecorder
        self.systemAudioRecorder = systemAudioRecorder
        self.outputDirectoryURL = outputDirectoryURL
    }

    var currentDuration: TimeInterval {
        max(microphoneRecorder.currentDuration, systemAudioRecorder.currentDuration)
    }

    var requiresMicrophonePermission: Bool {
        true
    }

    func validateRecordingPrerequisites() async -> AppError? {
        if let microphoneError = await microphoneRecorder.validateRecordingPrerequisites() {
            return microphoneError
        }

        return await systemAudioRecorder.validateRecordingPrerequisites()
    }

    func validateRecordingActivation() async -> AppError? {
        if let microphoneError = await microphoneRecorder.validateRecordingActivation() {
            return microphoneError
        }

        return await systemAudioRecorder.validateRecordingActivation()
    }

    func startRecording() async throws {
        guard !isRecording else {
            throw AppError.recordingFailure("A recording session is already active.")
        }

        do {
            try await systemAudioRecorder.startRecording()
            do {
                try await microphoneRecorder.startRecording()
            } catch {
                await systemAudioRecorder.cancelRecording(preserveFile: false)
                throw error
            }
            isRecording = true
            recordingLogger.info(
                "mixed_recording_started",
                "Microphone and system audio recording started successfully."
            )
        } catch let error as AppError {
            recordingLogger.error("mixed_recording_start_failed", error.userMessage)
            throw error
        } catch {
            recordingLogger.error("mixed_recording_start_failed", error.localizedDescription)
            throw AppError.recordingFailure(error.localizedDescription)
        }
    }

    func stopRecording() async throws -> RecordedAudio {
        guard isRecording else {
            throw AppError.recordingFailure("There is no active recording.")
        }

        isRecording = false

        var systemResult: Result<RecordedAudio, Error>?
        var microphoneResult: Result<RecordedAudio, Error>?

        do {
            systemResult = .success(try await systemAudioRecorder.stopRecording())
        } catch {
            systemResult = .failure(error)
        }

        do {
            microphoneResult = .success(try await microphoneRecorder.stopRecording())
        } catch {
            microphoneResult = .failure(error)
        }

        guard let systemResult else {
            throw AppError.recordingFailure("System audio recording was unavailable.")
        }
        guard let microphoneResult else {
            throw AppError.recordingFailure("Microphone recording was unavailable.")
        }

        let systemAudio = try systemResult.get()
        let microphoneAudio = try microphoneResult.get()

        let outputURL = makeMixedRecordingURL()
        let mixedAudio = try await mixAudioFiles(
            microphoneAudio: microphoneAudio,
            systemAudio: systemAudio,
            outputURL: outputURL
        )

        recordingLogger.info(
            "mixed_recording_stopped",
            "Microphone and system audio recording finished successfully.",
            metadata: [
                "file_name": mixedAudio.fileURL.lastPathComponent,
                "duration_seconds": String(format: "%.2f", mixedAudio.duration)
            ]
        )

        return mixedAudio
    }

    func cancelRecording(preserveFile: Bool) async {
        guard isRecording else {
            return
        }

        isRecording = false
        await microphoneRecorder.cancelRecording(preserveFile: preserveFile)
        await systemAudioRecorder.cancelRecording(preserveFile: preserveFile)
    }

    private func mixAudioFiles(
        microphoneAudio: RecordedAudio,
        systemAudio: RecordedAudio,
        outputURL: URL
    ) async throws -> RecordedAudio {
        try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: outputURL)

        let composition = AVMutableComposition()
        var mixParameters: [AVAudioMixInputParameters] = []

        try await addAudioTrack(
            fileURL: systemAudio.fileURL,
            to: composition,
            volume: 1.0,
            mixParameters: &mixParameters
        )
        try await addAudioTrack(
            fileURL: microphoneAudio.fileURL,
            to: composition,
            volume: 1.0,
            mixParameters: &mixParameters
        )

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParameters

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppError.recordingFailure("The mixed audio file could not be prepared.")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.audioMix = audioMix

        let exportBridge = MixedAssetExportSessionBridge(exportSession)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportBridge.session.exportAsynchronously {
                switch exportBridge.session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(
                        throwing: exportBridge.session.error ?? AppError.recordingFailure("The mixed audio export failed.")
                    )
                case .cancelled:
                    continuation.resume(throwing: AppError.recordingFailure("The mixed audio export was cancelled."))
                default:
                    continuation.resume(throwing: AppError.recordingFailure("The mixed audio export did not complete."))
                }
            }
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 0 else {
            throw AppError.recordingFailure("The mixed audio file was empty.")
        }

        return RecordedAudio(
            fileURL: outputURL,
            duration: max(microphoneAudio.duration, systemAudio.duration)
        )
    }

    private func addAudioTrack(
        fileURL: URL,
        to composition: AVMutableComposition,
        volume: Float,
        mixParameters: inout [AVAudioMixInputParameters]
    ) async throws {
        let asset = AVURLAsset(url: fileURL)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AppError.recordingFailure("The recording at \(fileURL.lastPathComponent) did not contain an audio track.")
        }
        let duration = try await asset.load(.duration)

        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AppError.recordingFailure("The mixed audio track could not be created.")
        }

        try compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceTrack,
            at: .zero
        )

        let parameters = AVMutableAudioMixInputParameters(track: compositionTrack)
        parameters.setVolume(volume, at: .zero)
        mixParameters.append(parameters)
    }

    private func makeMixedRecordingURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        return outputDirectoryURL
            .appendingPathComponent("\(timestamp)-mixed-recording-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }
}

private final class MixedAssetExportSessionBridge: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
