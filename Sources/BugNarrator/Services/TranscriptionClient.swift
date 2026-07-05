@preconcurrency import AVFoundation
import Foundation

actor TranscriptionClient: TranscriptionServing {
    private let session: URLSession
    private let fileManager: FileManager
    private let transcriptionChunker: any TranscriptionChunking
    private let audioUploadPolicy: AudioUploadPolicy
    private let qualityInspector: TranscriptQualityInspector
    private let requestFactory = TranscriptionRequestFactory()
    private let logger = DiagnosticsLogger(category: .transcription)

    init(
        session: URLSession? = nil,
        fileManager: FileManager = .default,
        transcriptionChunker: (any TranscriptionChunking)? = nil,
        audioUploadPolicy: AudioUploadPolicy? = nil,
        qualityInspector: TranscriptQualityInspector = TranscriptQualityInspector()
    ) {
        self.fileManager = fileManager
        self.transcriptionChunker = transcriptionChunker ?? DefaultTranscriptionChunker()
        self.audioUploadPolicy = audioUploadPolicy ?? AudioUploadPolicy(fileManager: fileManager)
        self.qualityInspector = qualityInspector
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 180
            configuration.timeoutIntervalForResource = 300
            self.session = URLSession(configuration: configuration)
        }
    }

    func transcribe(fileURL: URL, apiKey: String, request: TranscriptionRequest) async throws -> TranscriptionResult {
        _ = try validateRecordingSource(at: fileURL)
        await logLongRecordingIfNeeded(fileURL: fileURL)

        let fallbackChunk = TranscriptionAudioChunk(fileURL: fileURL, startTime: 0, isTemporary: false)
        let chunks = await preparedChunks(for: fileURL, fallback: fallbackChunk)

        if chunks.count == 1 {
            defer { cleanupTemporaryChunks(chunks) }
            let chunk = chunks[0]
            let result = try await transcribeSingleFile(fileURL: chunk.fileURL, apiKey: apiKey, request: request)
            guard chunk.startTime > 0 else {
                return result
            }

            return TranscriptionResult(
                text: result.text,
                segments: result.segments.map { segment in
                    TranscriptionSegment(
                        start: segment.start + chunk.startTime,
                        end: segment.end + chunk.startTime,
                        text: segment.text
                    )
                },
                qualityFindings: result.qualityFindings
            )
        }

        logger.info(
            "transcription_chunked_requested",
            "Uploading chunked audio for transcription.",
            metadata: [
                "file_name": fileURL.lastPathComponent,
                "chunk_count": "\(chunks.count)",
                "model": request.model
            ]
        )

        defer { cleanupTemporaryChunks(chunks) }

        var transcriptParts: [String] = []
        var adjustedSegments: [TranscriptionSegment] = []

        for (index, chunk) in chunks.enumerated() {
            logger.debug(
                "transcription_chunk_upload",
                "Uploading a transcription chunk.",
                metadata: [
                    "chunk_index": "\(index + 1)",
                    "chunk_count": "\(chunks.count)",
                    "chunk_file_name": chunk.fileURL.lastPathComponent,
                    "chunk_start_seconds": String(format: "%.2f", chunk.startTime)
                ]
            )

            let result = try await transcribeSingleFile(fileURL: chunk.fileURL, apiKey: apiKey, request: request)
            transcriptParts.append(result.text.trimmingCharacters(in: .whitespacesAndNewlines))
            adjustedSegments.append(
                contentsOf: result.segments.map { segment in
                    TranscriptionSegment(
                        start: segment.start + chunk.startTime,
                        end: segment.end + chunk.startTime,
                        text: segment.text
                    )
                }
            )
        }

        let transcript = transcriptParts
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transcript.isEmpty else {
            logger.warning("transcription_empty", "The provider returned an empty transcript after chunked transcription.")
            throw AppError.emptyTranscript
        }

        let qualityFindings = qualityInspector.findings(for: transcript)
        logQualityFindings(qualityFindings, fileName: fileURL.lastPathComponent)
        logger.info(
            "transcription_chunked_completed",
            "Completed transcript received after chunked transcription.",
            metadata: [
                "character_count": "\(transcript.count)",
                "segments_count": "\(adjustedSegments.count)",
                "chunk_count": "\(chunks.count)"
            ]
        )

        return TranscriptionResult(
            text: transcript,
            segments: adjustedSegments,
            qualityFindings: qualityFindings
        )
    }

    private static let maxRetryAttempts = 3
    private static let initialBackoffSeconds: TimeInterval = 2

    private func transcribeSingleFile(
        fileURL: URL,
        apiKey: String,
        request: TranscriptionRequest
    ) async throws -> TranscriptionResult {
        var lastError: Error?

        for attempt in 0..<Self.maxRetryAttempts {
            do {
                return try await attemptTranscription(fileURL: fileURL, apiKey: apiKey, request: request, attempt: attempt)
            } catch let error as AppError {
                let isLastAttempt = attempt >= Self.maxRetryAttempts - 1
                if case .rateLimited(let retryAfter) = error, !isLastAttempt {
                    let delay = retryAfter ?? Self.exponentialBackoff(for: attempt)
                    let clampedDelay = min(delay, 60)
                    logger.warning(
                        "transcription_rate_limited_retrying",
                        "Rate limit hit. Backing off before retry.",
                        metadata: [
                            "attempt": "\(attempt + 1)",
                            "backoff_seconds": String(format: "%.1f", clampedDelay)
                        ]
                    )
                    try await Task.sleep(nanoseconds: UInt64(clampedDelay * 1_000_000_000))
                    lastError = error
                    continue
                }
                if Self.shouldRetryTransientFailure(error), !isLastAttempt {
                    let delay = Self.exponentialBackoff(for: attempt)
                    logger.warning(
                        "transcription_transient_failure_retrying",
                        "Transient transport failure. Backing off before retry.",
                        metadata: [
                            "attempt": "\(attempt + 1)",
                            "backoff_seconds": String(format: "%.1f", delay),
                            "error_type": Self.errorTypeForLogging(error)
                        ]
                    )
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    lastError = error
                    continue
                }
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw error
            }
        }

        throw lastError ?? AppError.transcriptionFailure("Transcription failed after retries.")
    }

    private static func exponentialBackoff(for attempt: Int) -> TimeInterval {
        initialBackoffSeconds * pow(2, Double(attempt))
    }

    private static func shouldRetryTransientFailure(_ error: AppError) -> Bool {
        switch error {
        case .networkTimeout, .networkFailure:
            return true
        default:
            return false
        }
    }

    private static func errorTypeForLogging(_ error: AppError) -> String {
        switch error {
        case .networkTimeout: return "network_timeout"
        case .networkFailure: return "network_failure"
        default: return "other"
        }
    }

    private func attemptTranscription(
        fileURL: URL,
        apiKey: String,
        request: TranscriptionRequest,
        attempt: Int
    ) async throws -> TranscriptionResult {
        let urlRequest = try makeURLRequest(fileURL: fileURL, apiKey: apiKey, request: request)
        if attempt == 0 {
            logger.info(
                "transcription_requested",
                "Uploading audio for transcription.",
                metadata: [
                    "file_name": fileURL.lastPathComponent,
                    "model": request.model,
                    "has_language_hint": request.languageHint == nil ? "no" : "yes",
                    "has_prompt": request.prompt == nil ? "no" : "yes"
                ]
            )
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            let httpResponse = response as? HTTPURLResponse

            guard let httpResponse else {
                throw AppError.transcriptionFailure("The server response was invalid.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                logger.warning(
                    "transcription_rejected",
                    "The provider rejected the transcription request.",
                    metadata: ["status_code": "\(httpResponse.statusCode)"]
                )
                throw OpenAIErrorMapper.mapResponse(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    fallback: AppError.transcriptionFailure,
                    responseHeaders: httpResponse.allHeaderFields
                )
            }

            let result: TranscriptionResult
            do {
                result = try VerboseTranscriptionResponseParser(qualityInspector: qualityInspector).parse(data)
            } catch AppError.emptyTranscript {
                logger.warning("transcription_empty", "The provider returned an empty transcript.")
                throw AppError.emptyTranscript
            }

            logQualityFindings(result.qualityFindings, fileName: fileURL.lastPathComponent)
            logger.info(
                "transcription_completed",
                "Completed transcript received.",
                metadata: [
                    "character_count": "\(result.text.count)",
                    "segments_count": "\(result.segments.count)"
                ]
            )
            return result
        } catch {
            logger.error(
                "transcription_failed",
                (error as? AppError)?.userMessage ?? error.localizedDescription
            )
            throw OpenAIErrorMapper.mapTransportError(error, fallback: AppError.transcriptionFailure)
        }
    }

    private func preparedChunks(
        for fileURL: URL,
        fallback fallbackChunk: TranscriptionAudioChunk
    ) async -> [TranscriptionAudioChunk] {
        do {
            return try await transcriptionChunker.chunks(for: fileURL)
        } catch {
            logger.warning(
                "transcription_chunking_unavailable",
                "BugNarrator could not prepare transcription chunks and will fall back to a single upload.",
                metadata: ["error": error.localizedDescription]
            )
            return [fallbackChunk]
        }
    }

    private func cleanupTemporaryChunks(_ chunks: [TranscriptionAudioChunk]) {
        for chunk in chunks where chunk.isTemporary {
            try? fileManager.removeItem(at: chunk.fileURL)
        }
    }

    func validateAPIKey(_ apiKey: String, apiBaseURL: URL) async throws {
        let request = makeValidationRequest(apiKey: apiKey, apiBaseURL: apiBaseURL)
        logger.info("openai_key_validation_requested", "Validating the provider connection.")

        do {
            let (data, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            guard let httpResponse else {
                throw AppError.transcriptionFailure("The server response was invalid.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                logger.warning(
                    "openai_key_validation_rejected",
                    "The provider validation request was rejected.",
                    metadata: ["status_code": "\(httpResponse.statusCode)"]
                )
                throw OpenAIErrorMapper.mapResponse(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    fallback: AppError.transcriptionFailure
                )
            }
            logger.info("openai_key_validation_succeeded", "The provider connection was validated.")
        } catch {
            logger.error(
                "openai_key_validation_failed",
                (error as? AppError)?.userMessage ?? error.localizedDescription
            )
            throw OpenAIErrorMapper.mapTransportError(error, fallback: AppError.transcriptionFailure)
        }
    }

    func validateAPIKey(_ apiKey: String) async throws {
        try await validateAPIKey(apiKey, apiBaseURL: TranscriptionRequestFactory.defaultAPIBaseURL)
    }

    func makeValidationRequest(
        apiKey: String,
        apiBaseURL: URL = TranscriptionRequestFactory.defaultAPIBaseURL
    ) -> URLRequest {
        requestFactory.validationRequest(apiKey: apiKey, apiBaseURL: apiBaseURL)
    }

    func makeURLRequest(fileURL: URL, apiKey: String, request: TranscriptionRequest) throws -> URLRequest {
        _ = try validateAudioFile(at: fileURL)

        let boundary = "Boundary-\(UUID().uuidString)"
        return try requestFactory.transcriptionRequest(
            apiKey: apiKey,
            transcriptionRequest: request,
            boundary: boundary,
            body: makeBody(fileURL: fileURL, request: request, boundary: boundary)
        )
    }

    func makeBody(fileURL: URL, request: TranscriptionRequest, boundary: String) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        var builder = MultipartFormDataBuilder(boundary: boundary)

        builder.appendField(named: "model", value: request.model)
        builder.appendField(named: "response_format", value: "verbose_json")
        builder.appendField(named: "temperature", value: "0")

        if let languageHint = request.languageHint, !languageHint.isEmpty {
            builder.appendField(named: "language", value: languageHint)
        }

        if let prompt = request.prompt, !prompt.isEmpty {
            builder.appendField(named: "prompt", value: prompt)
        }

        builder.appendFile(
            named: "file",
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType(for: fileURL),
            data: fileData
        )

        return builder.finalizedBody()
    }

    @discardableResult
    private func validateAudioFile(at fileURL: URL) throws -> AudioFileInspection {
        let inspection: AudioFileInspection
        do {
            inspection = try audioUploadPolicy.validate(fileURL: fileURL)
        } catch {
            logger.error(
                "transcription_audio_invalid",
                (error as? AppError)?.userMessage ?? error.localizedDescription,
                metadata: ["file_name": fileURL.lastPathComponent]
            )
            throw error
        }

        logger.debug(
            "transcription_audio_validated",
            "The recorded audio file passed local validation before upload.",
            metadata: [
                "file_name": fileURL.lastPathComponent,
                "file_size_bytes": "\(inspection.fileSizeBytes)"
            ]
        )
        return inspection
    }

    @discardableResult
    private func validateRecordingSource(at fileURL: URL) throws -> AudioFileInspection {
        let inspection: AudioFileInspection
        do {
            inspection = try audioUploadPolicy.validateRecordingSource(fileURL: fileURL)
        } catch {
            logger.error(
                "transcription_audio_invalid",
                (error as? AppError)?.userMessage ?? error.localizedDescription,
                metadata: ["file_name": fileURL.lastPathComponent]
            )
            throw error
        }

        logger.debug(
            "transcription_audio_source_validated",
            "The recorded audio source exists and can be prepared for upload.",
            metadata: [
                "file_name": fileURL.lastPathComponent,
                "file_size_bytes": "\(inspection.fileSizeBytes)"
            ]
        )
        return inspection
    }

    private func logLongRecordingIfNeeded(fileURL: URL) async {
        let asset = AVURLAsset(url: fileURL)
        guard let durationTime = try? await asset.load(.duration) else {
            return
        }

        let duration = CMTimeGetSeconds(durationTime)
        guard duration.isFinite, duration >= AudioUploadPolicy.warningDuration else {
            return
        }

        logger.warning(
            "transcription_audio_long_duration",
            "The recording is long enough that chunking or review should be expected.",
            metadata: [
                "file_name": fileURL.lastPathComponent,
                "duration_seconds": String(format: "%.2f", duration)
            ]
        )
    }

    private func logQualityFindings(_ findings: [TranscriptQualityFinding], fileName: String) {
        guard !findings.isEmpty else {
            return
        }

        logger.warning(
            "transcription_quality_findings",
            "Transcript quality checks found issues that should be reviewed.",
            metadata: [
                "file_name": fileName,
                "finding_count": "\(findings.count)",
                "finding_kinds": findings.map(\.kind.rawValue).joined(separator: ",")
            ]
        )
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        default:
            return "application/octet-stream"
        }
    }
}

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
