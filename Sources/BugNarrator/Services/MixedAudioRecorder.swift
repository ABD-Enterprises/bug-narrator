@preconcurrency import AVFoundation
import Foundation

@MainActor
final class MixedAudioRecorder: AudioRecording {
    private let recordingLogger = DiagnosticsLogger(category: .recording)
    private let microphoneRecorder: any AudioRecording
    private let systemAudioRecorder: any AudioRecording
    private let outputDirectoryURL: URL

    private var isRecording = false
    private var isStopping = false
    private var sourceStartTimes: MixedAudioSourceStartTimes?

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
            let systemAudioStartedAt = ProcessInfo.processInfo.systemUptime
            do {
                try await microphoneRecorder.startRecording()
            } catch {
                await systemAudioRecorder.cancelRecording(preserveFile: false)
                sourceStartTimes = nil
                throw error
            }
            let microphoneStartedAt = ProcessInfo.processInfo.systemUptime
            sourceStartTimes = MixedAudioSourceStartTimes(
                microphoneStartedAt: microphoneStartedAt,
                systemAudioStartedAt: systemAudioStartedAt
            )
            isRecording = true
            recordingLogger.info(
                "mixed_recording_started",
                "Microphone and system audio recording started successfully.",
                metadata: [
                    "microphone_start_offset_seconds": String(
                        format: "%.3f",
                        sourceStartTimes?.insertionOffsets.microphoneOffset ?? 0
                    )
                ]
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
        guard isRecording, !isStopping else {
            throw AppError.recordingFailure("There is no active recording.")
        }

        isStopping = true
        defer {
            isStopping = false
            isRecording = false
            sourceStartTimes = nil
        }

        async let systemStopResult = stopSystemAudioRecorder()
        async let microphoneStopResult = stopMicrophoneRecorder()
        let (systemResult, microphoneResult) = await (systemStopResult, microphoneStopResult)

        switch (systemResult, microphoneResult) {
        case (.failure, .success(let microphoneAudio)):
            try? FileManager.default.removeItem(at: microphoneAudio.fileURL)
        case (.success(let systemAudio), .failure):
            try? FileManager.default.removeItem(at: systemAudio.fileURL)
        default:
            break
        }

        let systemAudio = try systemResult.get()
        let microphoneAudio = try microphoneResult.get()

        let outputURL = makeMixedRecordingURL()
        let insertionOffsets = sourceStartTimes?.insertionOffsets ?? .zero
        let mixedAudio = try await mixAudioFiles(
            microphoneAudio: microphoneAudio,
            systemAudio: systemAudio,
            outputURL: outputURL,
            insertionOffsets: insertionOffsets
        )
        removeSourceAudioFiles(
            [microphoneAudio.fileURL, systemAudio.fileURL],
            preserving: mixedAudio.fileURL
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

    private func stopSystemAudioRecorder() async -> Result<RecordedAudio, Error> {
        do {
            return .success(try await systemAudioRecorder.stopRecording())
        } catch {
            return .failure(error)
        }
    }

    private func stopMicrophoneRecorder() async -> Result<RecordedAudio, Error> {
        do {
            return .success(try await microphoneRecorder.stopRecording())
        } catch {
            return .failure(error)
        }
    }

    private func removeSourceAudioFiles(_ sourceURLs: [URL], preserving outputURL: URL) {
        let preservedURL = outputURL.standardizedFileURL
        for sourceURL in sourceURLs where sourceURL.standardizedFileURL != preservedURL {
            try? FileManager.default.removeItem(at: sourceURL)
        }
    }

    func cancelRecording(preserveFile: Bool) async {
        guard isRecording else {
            return
        }

        // Allow cancel to override a hung stop so the user is never trapped.
        isStopping = false
        isRecording = false
        sourceStartTimes = nil
        await microphoneRecorder.cancelRecording(preserveFile: preserveFile)
        await systemAudioRecorder.cancelRecording(preserveFile: preserveFile)
    }

    private func mixAudioFiles(
        microphoneAudio: RecordedAudio,
        systemAudio: RecordedAudio,
        outputURL: URL,
        insertionOffsets: MixedAudioTrackInsertionOffsets
    ) async throws -> RecordedAudio {
        try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: outputURL)

        var mixSucceeded = false
        defer {
            if !mixSucceeded {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        let composition = AVMutableComposition()
        var mixParameters: [AVAudioMixInputParameters] = []

        try await addAudioTrack(
            fileURL: systemAudio.fileURL,
            to: composition,
            volume: 1.0,
            insertionTime: insertionOffsets.systemAudioInsertionTime,
            mixParameters: &mixParameters
        )
        try await addAudioTrack(
            fileURL: microphoneAudio.fileURL,
            to: composition,
            volume: 1.0,
            insertionTime: insertionOffsets.microphoneInsertionTime,
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

        mixSucceeded = true
        return RecordedAudio(
            fileURL: outputURL,
            duration: max(microphoneAudio.duration, systemAudio.duration)
        )
    }

    private func addAudioTrack(
        fileURL: URL,
        to composition: AVMutableComposition,
        volume: Float,
        insertionTime: CMTime,
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
            at: insertionTime
        )

        let parameters = AVMutableAudioMixInputParameters(track: compositionTrack)
        parameters.setVolume(volume, at: insertionTime)
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

struct MixedAudioSourceStartTimes {
    let microphoneStartedAt: TimeInterval
    let systemAudioStartedAt: TimeInterval

    var insertionOffsets: MixedAudioTrackInsertionOffsets {
        MixedAudioTrackInsertionOffsets(
            microphoneStartedAt: microphoneStartedAt,
            systemAudioStartedAt: systemAudioStartedAt
        )
    }
}

struct MixedAudioTrackInsertionOffsets: Equatable {
    static let zero = MixedAudioTrackInsertionOffsets(
        microphoneOffset: 0,
        systemAudioOffset: 0
    )

    let microphoneOffset: TimeInterval
    let systemAudioOffset: TimeInterval

    init(microphoneStartedAt: TimeInterval, systemAudioStartedAt: TimeInterval) {
        let earliestStart = min(microphoneStartedAt, systemAudioStartedAt)
        microphoneOffset = max(0, microphoneStartedAt - earliestStart)
        systemAudioOffset = max(0, systemAudioStartedAt - earliestStart)
    }

    private init(microphoneOffset: TimeInterval, systemAudioOffset: TimeInterval) {
        self.microphoneOffset = microphoneOffset
        self.systemAudioOffset = systemAudioOffset
    }

    var microphoneInsertionTime: CMTime {
        CMTime(seconds: microphoneOffset, preferredTimescale: 1_000_000)
    }

    var systemAudioInsertionTime: CMTime {
        CMTime(seconds: systemAudioOffset, preferredTimescale: 1_000_000)
    }
}

private final class MixedAssetExportSessionBridge: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
