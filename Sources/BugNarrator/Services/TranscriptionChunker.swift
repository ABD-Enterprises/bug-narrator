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
    /// One planned slice of the source audio: where it starts and how long it is.
    struct Span: Equatable, Sendable {
        let startTime: TimeInterval
        let duration: TimeInterval
    }

    private let maxChunkDuration: TimeInterval
    private let minimumTailDuration: TimeInterval

    /// - Parameters:
    ///   - maxChunkDuration: upper bound per chunk. 8 minutes of m4a is a few MB,
    ///     well inside the 25 MB the OpenAI transcription endpoint accepts, so a
    ///     tail merged onto the last chunk cannot push it over that limit.
    ///   - minimumTailDuration: a final slice shorter than this is folded into the
    ///     previous chunk instead of exported on its own. A recording of
    ///     8:00.5 used to yield a 0.5 s second chunk — a separate export and a
    ///     separate API call for half a second of audio — and a total one ulp
    ///     over a multiple of max yielded a tail of ~6e-14 s, well under the
    ///     0.1 s floor providers such as OpenAI enforce.
    init(maxChunkDuration: TimeInterval = 8 * 60, minimumTailDuration: TimeInterval = 1) {
        self.maxChunkDuration = maxChunkDuration
        self.minimumTailDuration = minimumTailDuration
    }

    /// The pure part: decide the spans for a recording of `totalDuration`. Kept
    /// synchronous and free of AVFoundation so the boundary math can be tested
    /// without an asset. An empty result means "do not chunk; send the file whole".
    static func plan(
        totalDuration: TimeInterval,
        maxChunkDuration: TimeInterval,
        minimumTailDuration: TimeInterval
    ) -> [Span] {
        guard totalDuration.isFinite, maxChunkDuration > 0, totalDuration > maxChunkDuration else {
            return []
        }

        var spans: [Span] = []
        var startTime: TimeInterval = 0
        while startTime < totalDuration {
            let remaining = totalDuration - startTime
            var duration = min(maxChunkDuration, remaining)
            // If what would be left after this chunk is a sub-threshold tail,
            // absorb it now rather than exporting it as its own chunk.
            let tailAfterThis = remaining - duration
            if tailAfterThis > 0, tailAfterThis < minimumTailDuration {
                duration = remaining
            }
            // A zero-length span would never advance startTime. The loop
            // condition already prevents it; this makes a future regression fail
            // loudly (an empty plan) instead of hanging the caller.
            guard duration > 0 else { return [] }
            spans.append(Span(startTime: startTime, duration: duration))
            startTime += duration
        }
        return spans
    }

    func chunks(for fileURL: URL) async throws -> [TranscriptionAudioChunk] {
        let asset = AVURLAsset(url: fileURL)
        let durationTime = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(durationTime)

        let spans = Self.plan(
            totalDuration: totalDuration,
            maxChunkDuration: maxChunkDuration,
            minimumTailDuration: minimumTailDuration
        )
        guard !spans.isEmpty else {
            return [TranscriptionAudioChunk(fileURL: fileURL, startTime: 0, isTemporary: false)]
        }

        var chunks: [TranscriptionAudioChunk] = []
        for span in spans {
            let chunkURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("BugNarrator-Chunk-\(UUID().uuidString)")
                .appendingPathExtension("m4a")

            try await exportChunk(
                from: asset,
                startTime: span.startTime,
                duration: span.duration,
                outputURL: chunkURL
            )

            chunks.append(
                TranscriptionAudioChunk(
                    fileURL: chunkURL,
                    startTime: span.startTime,
                    isTemporary: true
                )
            )
        }
        return chunks
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
