import Combine
import Foundation

@MainActor
final class IssueExtractionController: ObservableObject {
    @Published private(set) var issueExtractionSessionID: UUID?

    private let sessionLibrary: SessionLibraryController
    private let issueExtractionService: any IssueExtracting
    private let logger: DiagnosticsLogger

    init(
        sessionLibrary: SessionLibraryController,
        issueExtractionService: any IssueExtracting,
        logger: DiagnosticsLogger = DiagnosticsLogger(category: .transcription)
    ) {
        self.sessionLibrary = sessionLibrary
        self.issueExtractionService = issueExtractionService
        self.logger = logger
    }

    func isExtractingIssues(for session: TranscriptSession) -> Bool {
        issueExtractionSessionID == session.id
    }

    func clearProgress() {
        issueExtractionSessionID = nil
    }

    func preflightIssueExtraction(
        for session: TranscriptSession,
        hasUsableAIProviderCredential: Bool,
        aiProviderCompatibilityIssue: String?,
        statusPhase: AppStatus.Phase
    ) -> AppError? {
        if let compatibilityIssue = aiProviderCompatibilityIssue {
            return .transcriptionFailure(compatibilityIssue)
        }

        guard hasUsableAIProviderCredential else {
            return .missingAPIKey
        }

        let transcript = session.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            return .emptyTranscript
        }

        guard statusPhase != .recording else {
            return .recordingFailure("Stop the current recording before extracting issues.")
        }

        return nil
    }

    func extractIssues(
        for session: TranscriptSession,
        apiKey: String,
        model: String,
        apiBaseURL: URL,
        completionLog: IssueExtractionCompletionLog
    ) async throws -> IssueExtractionResult {
        issueExtractionSessionID = session.id
        defer { issueExtractionSessionID = nil }

        let extraction = try await issueExtractionService.extractIssues(
            from: session,
            apiKey: apiKey,
            model: model,
            apiBaseURL: apiBaseURL
        )

        var updatedSession = session
        updatedSession.issueExtraction = extraction
        try sessionLibrary.persistUpdatedSession(updatedSession)

        logger.info(
            completionLog.eventName,
            completionLog.message,
            metadata: [
                "session_id": session.id.uuidString,
                "issue_count": "\(extraction.issues.count)"
            ]
        )
        return extraction
    }

    @discardableResult
    func updateExtractedIssue(_ updatedIssue: ExtractedIssue, in sessionID: UUID) throws -> Bool {
        guard var session = sessionLibrary.editableSession(with: sessionID),
              var extraction = session.issueExtraction,
              let issueIndex = extraction.issues.firstIndex(where: { $0.id == updatedIssue.id }) else {
            return false
        }

        extraction.issues[issueIndex] = updatedIssue
        session.issueExtraction = extraction
        try sessionLibrary.persistUpdatedSession(session)
        return true
    }

    @discardableResult
    func setIssueSelection(_ isSelected: Bool, issueID: UUID, in sessionID: UUID) throws -> Bool {
        guard var session = sessionLibrary.editableSession(with: sessionID),
              var extraction = session.issueExtraction,
              let issueIndex = extraction.issues.firstIndex(where: { $0.id == issueID }) else {
            return false
        }

        extraction.issues[issueIndex].isSelectedForExport = isSelected
        session.issueExtraction = extraction
        try sessionLibrary.persistUpdatedSession(session)
        return true
    }

    @discardableResult
    func setAllIssuesSelected(_ isSelected: Bool, in sessionID: UUID) throws -> Bool {
        guard var session = sessionLibrary.editableSession(with: sessionID),
              var extraction = session.issueExtraction else {
            return false
        }

        extraction.issues = extraction.issues.map { issue in
            var updatedIssue = issue
            updatedIssue.isSelectedForExport = isSelected
            return updatedIssue
        }
        session.issueExtraction = extraction
        try sessionLibrary.persistUpdatedSession(session)
        return true
    }
}

struct IssueExtractionCompletionLog {
    let eventName: String
    let message: String

    static let manual = IssueExtractionCompletionLog(
        eventName: "issue_extraction_completed",
        message: "Issue extraction finished successfully."
    )

    static let postTranscription = IssueExtractionCompletionLog(
        eventName: "issue_extraction_completed_after_transcription",
        message: "Automatic issue extraction completed after transcription."
    )
}
