@preconcurrency import AVFoundation
import Foundation

struct TranscriptionRequest: Sendable {
    let model: String
    let languageHint: String?
    let prompt: String?
}

struct TranscriptionResult: Sendable {
    let text: String
    let segments: [TranscriptionSegment]
    let qualityFindings: [TranscriptQualityFinding]

    init(
        text: String,
        segments: [TranscriptionSegment],
        qualityFindings: [TranscriptQualityFinding] = []
    ) {
        self.text = text
        self.segments = segments
        self.qualityFindings = qualityFindings
    }
}

struct TranscriptionSegment: Decodable, Sendable {
    let start: Double
    let end: Double
    let text: String
}

actor TranscriptionClient: TranscriptionServing {
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let validationEndpoint = URL(string: "https://api.openai.com/v1/models")!
    private let session: URLSession
    private let fileManager: FileManager
    private let transcriptionChunker: any TranscriptionChunking
    private let audioUploadPolicy: AudioUploadPolicy
    private let qualityInspector: TranscriptQualityInspector
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
        _ = try validateAudioFile(at: fileURL)
        await logLongRecordingIfNeeded(fileURL: fileURL)

        let fallbackChunk = TranscriptionAudioChunk(fileURL: fileURL, startTime: 0, isTemporary: false)
        let chunks = await preparedChunks(for: fileURL, fallback: fallbackChunk)

        if chunks.count == 1 {
            return try await transcribeSingleFile(fileURL: fileURL, apiKey: apiKey, request: request)
        }

        logger.info(
            "transcription_chunked_requested",
            "Uploading chunked audio to OpenAI for transcription.",
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
                "Uploading a transcription chunk to OpenAI.",
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
            logger.warning("transcription_empty", "OpenAI returned an empty transcript after chunked transcription.")
            throw AppError.emptyTranscript
        }

        let qualityFindings = qualityInspector.findings(for: transcript)
        logQualityFindings(qualityFindings, fileName: fileURL.lastPathComponent)
        logger.info(
            "transcription_chunked_completed",
            "OpenAI returned a completed transcript after chunked transcription.",
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

    private func transcribeSingleFile(
        fileURL: URL,
        apiKey: String,
        request: TranscriptionRequest
    ) async throws -> TranscriptionResult {
        let urlRequest = try makeURLRequest(fileURL: fileURL, apiKey: apiKey, request: request)
        logger.info(
            "transcription_requested",
            "Uploading audio to OpenAI for transcription.",
            metadata: [
                "file_name": fileURL.lastPathComponent,
                "model": request.model,
                "has_language_hint": request.languageHint == nil ? "no" : "yes",
                "has_prompt": request.prompt == nil ? "no" : "yes"
            ]
        )

        do {
            let (data, response) = try await session.data(for: urlRequest)
            let httpResponse = response as? HTTPURLResponse

            guard let httpResponse else {
                throw AppError.transcriptionFailure("The server response was invalid.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                logger.warning(
                    "transcription_rejected",
                    "OpenAI rejected the transcription request.",
                    metadata: ["status_code": "\(httpResponse.statusCode)"]
                )
                throw OpenAIErrorMapper.mapResponse(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    fallback: AppError.transcriptionFailure
                )
            }

            let result = try JSONDecoder().decode(VerboseTranscriptionResponse.self, from: data)
            let transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !transcript.isEmpty else {
                logger.warning("transcription_empty", "OpenAI returned an empty transcript.")
                throw AppError.emptyTranscript
            }

            let qualityFindings = qualityInspector.findings(for: transcript)
            logQualityFindings(qualityFindings, fileName: fileURL.lastPathComponent)
            logger.info(
                "transcription_completed",
                "OpenAI returned a completed transcript.",
                metadata: [
                    "character_count": "\(transcript.count)",
                    "segments_count": "\(result.segments?.count ?? 0)"
                ]
            )
            return TranscriptionResult(
                text: transcript,
                segments: result.segments ?? [],
                qualityFindings: qualityFindings
            )
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

    func validateAPIKey(_ apiKey: String) async throws {
        let request = makeValidationRequest(apiKey: apiKey)
        logger.info("openai_key_validation_requested", "Validating the OpenAI API key.")

        do {
            let (data, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            guard let httpResponse else {
                throw AppError.transcriptionFailure("The server response was invalid.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                logger.warning(
                    "openai_key_validation_rejected",
                    "The OpenAI API key validation request was rejected.",
                    metadata: ["status_code": "\(httpResponse.statusCode)"]
                )
                throw OpenAIErrorMapper.mapResponse(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    fallback: AppError.transcriptionFailure
                )
            }
            logger.info("openai_key_validation_succeeded", "The OpenAI API key was accepted.")
        } catch {
            logger.error(
                "openai_key_validation_failed",
                (error as? AppError)?.userMessage ?? error.localizedDescription
            )
            throw OpenAIErrorMapper.mapTransportError(error, fallback: AppError.transcriptionFailure)
        }
    }

    func makeValidationRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: validationEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    func makeURLRequest(fileURL: URL, apiKey: String, request: TranscriptionRequest) throws -> URLRequest {
        _ = try validateAudioFile(at: fileURL)

        let boundary = "Boundary-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try makeBody(fileURL: fileURL, request: request, boundary: boundary)

        return urlRequest
    }

    func makeBody(fileURL: URL, request: TranscriptionRequest, boundary: String) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        var body = Data()

        appendField(named: "model", value: request.model, boundary: boundary, to: &body)
        appendField(named: "response_format", value: "verbose_json", boundary: boundary, to: &body)
        appendField(named: "temperature", value: "0", boundary: boundary, to: &body)

        if let languageHint = request.languageHint, !languageHint.isEmpty {
            appendField(named: "language", value: languageHint, boundary: boundary, to: &body)
        }

        if let prompt = request.prompt, !prompt.isEmpty {
            appendField(named: "prompt", value: prompt, boundary: boundary, to: &body)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(mimeType(for: fileURL))\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
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

    private func appendField(named name: String, value: String, boundary: String, to body: inout Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
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

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AppError.transcriptionFailure("The recorded audio chunk could not be created.")
        }
    }
}

private final class AssetExportSessionBridge: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

private struct VerboseTranscriptionResponse: Decodable {
    let text: String
    let segments: [TranscriptionSegment]?
}
