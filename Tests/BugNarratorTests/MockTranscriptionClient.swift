import Foundation
import XCTest
@testable import BugNarrator

actor MockTranscriptionClient: TranscriptionServing {
    private var queuedResults: [Result<TranscriptionResult, Error>] = []
    private var validationResults: [Result<Void, Error>] = []
    private(set) var callCount = 0
    private(set) var requestedFileURLs: [URL] = []
    private(set) var requestedModels: [String] = []
    private(set) var validationCallCount = 0
    private(set) var requestedValidationAPIKeys: [String] = []
    private(set) var requestedValidationBaseURLs: [URL] = []

    func enqueue(_ result: Result<TranscriptionResult, Error>) {
        queuedResults.append(result)
    }

    func enqueueValidation(_ result: Result<Void, Error>) {
        validationResults.append(result)
    }

    func transcribe(fileURL: URL, apiKey: String, request: TranscriptionRequest) async throws -> TranscriptionResult {
        callCount += 1
        requestedFileURLs.append(fileURL)
        requestedModels.append(request.model)

        guard !queuedResults.isEmpty else {
            throw AppError.transcriptionFailure("No mock transcription result was configured.")
        }

        return try queuedResults.removeFirst().get()
    }

    func validateAPIKey(_ apiKey: String, apiBaseURL: URL) async throws {
        validationCallCount += 1
        requestedValidationAPIKeys.append(apiKey)
        requestedValidationBaseURLs.append(apiBaseURL)

        if validationResults.isEmpty {
            return
        }

        try validationResults.removeFirst().get()
    }
}

