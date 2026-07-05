import Combine
import Foundation

enum IssueExtractionStatusPresenter {
    static var manualProgressStatus: AppStatus {
        .transcribing("Running issue extraction with a 10-second time limit...")
    }

    static func manualCompletionStatus(issueCount: Int) -> AppStatus {
        .success("Extracted \(issueCount) review issues.")
    }
}

@MainActor
final class ManualIssueExtractionStatusPresenter {
    private let errorPresenter: AppErrorPresenter
    private let showTranscriptWindow: () -> Void
    private let showSettingsWindow: () -> Void
    private let logger: DiagnosticsLogger

    init(
        errorPresenter: AppErrorPresenter,
        showTranscriptWindow: @escaping () -> Void,
        showSettingsWindow: @escaping () -> Void,
        logger: DiagnosticsLogger = DiagnosticsLogger(category: .transcription)
    ) {
        self.errorPresenter = errorPresenter
        self.showTranscriptWindow = showTranscriptWindow
        self.showSettingsWindow = showSettingsWindow
        self.logger = logger
    }

    func presentRequestStarted(sessionID: UUID) {
        errorPresenter.setStatus(IssueExtractionStatusPresenter.manualProgressStatus)
        logger.info(
            "issue_extraction_requested",
            "Issue extraction was requested for the selected transcript.",
            metadata: ["session_id": sessionID.uuidString]
        )
    }

    func presentCompletion(issueCount: Int) {
        errorPresenter.setStatus(IssueExtractionStatusPresenter.manualCompletionStatus(issueCount: issueCount))
        showTranscriptWindow()
    }

    func presentPreflightFailure(_ error: AppError, sessionID: UUID) {
        logger.warning(
            "issue_extraction_preflight_failed",
            error.userMessage,
            metadata: ["session_id": sessionID.uuidString]
        )
        presentError(error)
    }

    func presentFailure(_ error: Error) {
        presentError(error, fallback: { .issueExtractionFailure($0) })
    }

    private func presentError(
        _ error: Error,
        fallback: (String) -> AppError = { .transcriptionFailure($0) }
    ) {
        let result = errorPresenter.presentError(error, operation: .postTranscription, fallback: fallback)
        if result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
    }
}

@MainActor
final class IssueExtractionFailurePresenter {
    private let errorPresenter: AppErrorPresenter
    var prepareErrorPresentationSideEffects: () -> Void

    init(
        errorPresenter: AppErrorPresenter,
        prepareErrorPresentationSideEffects: @escaping () -> Void = {}
    ) {
        self.errorPresenter = errorPresenter
        self.prepareErrorPresentationSideEffects = prepareErrorPresentationSideEffects
    }

    func presentFailure(_ error: Error) {
        prepareErrorPresentationSideEffects()
        _ = errorPresenter.presentError(error, operation: .issueExtraction, fallback: { .storageFailure($0) })
    }
}

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
