import AudioToolbox
@preconcurrency import AVFoundation
import Foundation

@MainActor
final class SystemAudioRecorder: AudioRecording {
    private let recordingLogger = DiagnosticsLogger(category: .recording)
    private let recoveryDirectoryURL: URL
    private let ioQueue = DispatchQueue(label: "BugNarrator.SystemAudioRecorder.IO", qos: .userInitiated)

    private var tapSession: SystemAudioTapSession?
    private var activeWriter: SystemAudioFileWriter?
    private var currentFileURL: URL?
    private var recordingStartedAt: Date?

    init(
        recoveryDirectoryURL: URL = AppSupportLocation.appDirectory()
            .appendingPathComponent("RecoveredRecordings", isDirectory: true)
    ) {
        self.recoveryDirectoryURL = recoveryDirectoryURL
    }

    var currentDuration: TimeInterval {
        guard let recordingStartedAt else {
            return 0
        }

        return Date().timeIntervalSince(recordingStartedAt)
    }

    var requiresMicrophonePermission: Bool {
        false
    }

    func validateRecordingPrerequisites() async -> AppError? {
        guard tapSession == nil, activeWriter == nil else {
            return .recordingFailure("A recording session is already active.")
        }

        guard #available(macOS 14.2, *) else {
            return .systemAudioUnavailable("System audio capture requires macOS 14.2 or later.")
        }

        logAggregateDeviceCleanupSummary(SystemAudioTapSession.cleanupStaleAggregateDevices())

        do {
            let probe = SystemAudioTapSession()
            do {
                _ = try probe.prepare()
                probe.invalidate()
            } catch {
                probe.invalidate()
                throw error
            }
            return nil
        } catch let error as AppError {
            return error
        } catch {
            return .systemAudioUnavailable(systemAudioRecoveryMessage(details: error.localizedDescription))
        }
    }

    func validateRecordingActivation() async -> AppError? {
        await validateRecordingPrerequisites()
    }

    func startRecording() async throws {
        recordingLogger.info("system_audio_recording_start_requested", "System audio recording start was requested.")

        guard tapSession == nil, activeWriter == nil else {
            throw AppError.recordingFailure("A recording session is already active.")
        }

        guard #available(macOS 14.2, *) else {
            throw AppError.systemAudioUnavailable("System audio capture requires macOS 14.2 or later.")
        }

        logAggregateDeviceCleanupSummary(SystemAudioTapSession.cleanupStaleAggregateDevices())

        let session = SystemAudioTapSession()
        var writer: SystemAudioFileWriter?

        do {
            try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
            let format = try session.prepare()
            let fileURL = makeRecoverableRecordingURL()
            let preparedWriter = try SystemAudioFileWriter(fileURL: fileURL, format: format)
            writer = preparedWriter

            try session.start(on: ioQueue, writer: preparedWriter)

            tapSession = session
            activeWriter = writer
            currentFileURL = fileURL
            recordingStartedAt = Date()

            recordingLogger.info(
                "system_audio_recording_started",
                "System audio recording started successfully.",
                metadata: ["file_name": fileURL.lastPathComponent]
            )
        } catch let error as AppError {
            session.invalidate()
            try? writer?.close()
            recordingLogger.error("system_audio_recording_start_failed", error.userMessage)
            throw error
        } catch {
            session.invalidate()
            try? writer?.close()
            recordingLogger.error("system_audio_recording_start_failed", error.localizedDescription)
            throw AppError.systemAudioUnavailable(systemAudioRecoveryMessage(details: error.localizedDescription))
        }
    }

    func stopRecording() async throws -> RecordedAudio {
        guard let tapSession, let activeWriter, let currentFileURL else {
            throw AppError.recordingFailure("There is no active recording.")
        }

        let duration = currentDuration
        recordingLogger.info(
            "system_audio_recording_stop_requested",
            "System audio recording is being finalized.",
            metadata: ["file_name": currentFileURL.lastPathComponent]
        )

        tapSession.invalidate()
        await ioQueue.drain()
        try await Self.closeWriter(activeWriter)
        cleanupActiveState()

        try await Self.validateRecordedAudioFile(at: currentFileURL)

        recordingLogger.info(
            "system_audio_recording_stopped",
            "System audio recording finished successfully.",
            metadata: [
                "file_name": currentFileURL.lastPathComponent,
                "duration_seconds": String(format: "%.2f", duration)
            ]
        )

        return RecordedAudio(fileURL: currentFileURL, duration: duration)
    }

    func cancelRecording(preserveFile: Bool) async {
        let fileURL = currentFileURL
        tapSession?.invalidate()
        await ioQueue.drain()
        if let activeWriter {
            try? await Self.closeWriter(activeWriter)
        }
        cleanupActiveState()

        guard !preserveFile, let fileURL else {
            return
        }

        await Self.removeItemIfPresent(at: fileURL)
    }

    private func cleanupActiveState() {
        tapSession = nil
        activeWriter = nil
        currentFileURL = nil
        recordingStartedAt = nil
    }

    private static func closeWriter(_ writer: SystemAudioFileWriter) async throws {
        try await Task.detached(priority: .userInitiated) {
            try writer.close()
        }.value
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
            throw AppError.recordingFailure("The recorded system audio file could not be found.")
        }

        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 0 else {
            throw AppError.recordingFailure("The recorded system audio file was empty.")
        }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            guard audioFile.fileFormat.sampleRate > 0, audioFile.length > 0 else {
                throw AppError.recordingFailure("The recorded system audio file did not contain playable audio.")
            }
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.recordingFailure("The recorded system audio file could not be read.")
        }
    }

    private func makeRecoverableRecordingURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        return recoveryDirectoryURL
            .appendingPathComponent("\(timestamp)-system-audio-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }

    private func systemAudioRecoveryMessage(details: String) -> String {
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = trimmedDetails.isEmpty ? "" : " \(trimmedDetails)"
        return "Open System Settings > Privacy & Security > Screen & System Audio Recording, enable BugNarrator, then try again.\(suffix)"
    }

    private func logAggregateDeviceCleanupSummary(_ summary: SystemAudioAggregateDeviceCleanupSummary) {
        guard summary.destroyedCount > 0 || summary.failedCount > 0 || summary.scanFailed else {
            return
        }

        let levelMessage = summary.failedCount > 0 || summary.scanFailed
            ? "BugNarrator found stale system audio devices, but some could not be cleaned up."
            : "BugNarrator cleaned up stale system audio devices before recording."
        let metadata = [
            "inspected_count": "\(summary.inspectedCount)",
            "destroyed_count": "\(summary.destroyedCount)",
            "failed_count": "\(summary.failedCount)",
            "scan_failed": "\(summary.scanFailed)"
        ]

        if summary.failedCount > 0 || summary.scanFailed {
            recordingLogger.warning(
                "system_audio_stale_aggregate_cleanup_partial",
                levelMessage,
                metadata: metadata
            )
        } else {
            recordingLogger.info(
                "system_audio_stale_aggregate_cleanup_succeeded",
                levelMessage,
                metadata: metadata
            )
        }
    }
}

private extension DispatchQueue {
    func drain() async {
        await withCheckedContinuation { continuation in
            async {
                continuation.resume()
            }
        }
    }
}

