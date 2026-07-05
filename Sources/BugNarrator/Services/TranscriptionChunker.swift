@preconcurrency import AVFoundation
import Foundation

struct TranscriptionAudioChunk: Sendable {
    let fileURL: URL
    let startTime: TimeInterval
    let isTemporary: Bool
}

protocol TranscriptionChunking: Sendable {
    func chunks(for fileURL: URL) async throws -> [TranscriptionAudioChunk]
}

struct DefaultTranscriptionChunker: TranscriptionChunking {
    private let maxChunkDuration: TimeInterval

    init(maxChunkDuration: TimeInterval = 8 * 60) {
        self.maxChunkDuration = maxChunkDuration
    }

    func chunks(for fileURL: URL) async throws -> [TranscriptionAudioChunk] {
        let asset = AVURLAsset(url: fileURL)
        let durationTime = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(durationTime)

        guard totalDuration.isFinite, totalDuration > maxChunkDuration else {
            return [TranscriptionAudioChunk(fileURL: fileURL, startTime: 0, isTemporary: false)]
        }

        var chunks: [TranscriptionAudioChunk] = []
        var startTime: TimeInterval = 0

        while startTime < totalDuration {
            let chunkDuration = min(maxChunkDuration, totalDuration - startTime)
            let chunkURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("BugNarrator-Chunk-\(UUID().uuidString)")
                .appendingPathExtension("m4a")

            try await exportChunk(
                from: asset,
                startTime: startTime,
                duration: chunkDuration,
                outputURL: chunkURL
            )

            chunks.append(
                TranscriptionAudioChunk(
                    fileURL: chunkURL,
                    startTime: startTime,
                    isTemporary: true
                )
            )
            startTime += chunkDuration
        }

        return chunks.isEmpty
            ? [TranscriptionAudioChunk(fileURL: fileURL, startTime: 0, isTemporary: false)]
            : chunks
    }

    private func exportChunk(
        from asset: AVURLAsset,
        startTime: TimeInterval,
        duration: TimeInterval,
        outputURL: URL
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppError.transcriptionFailure("The recorded audio could not be prepared for chunked transcription.")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        let exportBridge = AssetExportSessionBridge(exportSession)

        // AVAssetExportSession's completion-handler export has no internal
        // timeout, so a hung encoder would suspend the transcription pipeline
        // forever. Race it against a deadline (scaled to the chunk length, with
        // a generous floor) and cancel the export if the deadline wins.
        let timeoutSeconds = max(Self.minimumChunkExportTimeout, duration * Self.chunkExportTimeoutMultiplier)
        do {
            try await withAsyncTimeout(
                seconds: timeoutSeconds,
                operation: {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        exportBridge.session.exportAsynchronously {
                            switch exportBridge.session.status {
                            case .completed:
                                continuation.resume()
                            case .failed:
                                continuation.resume(throwing: exportBridge.session.error ?? AppError.transcriptionFailure("The recorded audio chunk export failed."))
                            case .cancelled:
                                continuation.resume(throwing: AppError.transcriptionFailure("The recorded audio chunk export was cancelled."))
                            default:
                                continuation.resume(throwing: AppError.transcriptionFailure("The recorded audio chunk export did not complete successfully."))
                            }
                        }
                    }
                },
                onTimeout: {
                    exportBridge.session.cancelExport()
                }
            )
        } catch is AsyncTimeoutError {
            throw AppError.transcriptionFailure("The recorded audio chunk export timed out.")
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AppError.transcriptionFailure("The recorded audio chunk could not be created.")
        }
    }

    /// Minimum wall-clock budget for re-encoding a single transcription chunk.
    private static let minimumChunkExportTimeout: TimeInterval = 120
    /// Per-second-of-audio multiplier applied on top of the floor for long chunks.
    private static let chunkExportTimeoutMultiplier: Double = 3
}

// Thread-safety invariant: a bridge instance wraps one AVAssetExportSession used
// by exactly one `exportChunk` call. The session is fully configured before
// `exportAsynchronously` starts; thereafter the only concurrent touch is
// `cancelExport()` from the timeout task, which Apple documents as safe to call
// while an export is in flight. No other aliasing exists, so `@unchecked` holds.
private final class AssetExportSessionBridge: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
