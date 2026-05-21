import XCTest
@testable import BugNarrator

@MainActor
final class IssueExtractionControllerTests: XCTestCase {
    func testStatusPresenterMapsManualExtractionStatuses() {
        XCTAssertEqual(
            IssueExtractionStatusPresenter.manualProgressStatus,
            .transcribing("Running issue extraction with a 10-second time limit...")
        )
        XCTAssertEqual(
            IssueExtractionStatusPresenter.manualCompletionStatus(issueCount: 3),
            .success("Extracted 3 review issues.")
        )
    }

    func testManualIssueExtractionPresenterSetsProgressStatus() {
        let harness = makeManualIssueExtractionPresenter()

        harness.presenter.presentRequestStarted(sessionID: UUID())

        XCTAssertEqual(harness.presentationState.status, IssueExtractionStatusPresenter.manualProgressStatus)
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertEqual(harness.transcriptWindowOpenCount(), 0)
        XCTAssertEqual(harness.settingsWindowOpenCount(), 0)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testManualIssueExtractionPresenterSetsCompletionStatusAndShowsTranscriptWindow() {
        let harness = makeManualIssueExtractionPresenter(status: .transcribing("Running extraction."))

        harness.presenter.presentCompletion(issueCount: 2)

        XCTAssertEqual(
            harness.presentationState.status,
            IssueExtractionStatusPresenter.manualCompletionStatus(issueCount: 2)
        )
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertEqual(harness.transcriptWindowOpenCount(), 1)
        XCTAssertEqual(harness.settingsWindowOpenCount(), 0)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testManualIssueExtractionPresenterPresentsPreflightFailure() {
        let harness = makeManualIssueExtractionPresenter()
        let expectedError = AppError.missingAPIKey

        harness.presenter.presentPreflightFailure(expectedError, sessionID: UUID())

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.transcriptWindowOpenCount(), 0)
        XCTAssertEqual(harness.settingsWindowOpenCount(), 1)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata["operation"], "post_transcription")
    }

    func testManualIssueExtractionPresenterNormalizesExtractionFailure() {
        let harness = makeManualIssueExtractionPresenter(status: .transcribing("Running extraction."))
        let error = NSError(
            domain: "BugNarratorTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Extraction timed out"]
        )
        let expectedError = AppError.issueExtractionFailure("Extraction timed out")

        harness.presenter.presentFailure(error)

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.transcriptWindowOpenCount(), 0)
        XCTAssertEqual(harness.settingsWindowOpenCount(), 0)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata["operation"], "post_transcription")
    }

    func testIssueMutationFailurePresenterNormalizesStorageFailure() {
        let harness = makeIssueMutationFailurePresenter()
        let error = NSError(
            domain: "BugNarratorTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not save issue"]
        )
        let expectedError = AppError.storageFailure("Could not save issue")

        harness.presenter.presentFailure(error)

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata["operation"], "session_library")
    }

    func testIssueMutationFailurePresenterRunsCleanupHookOnFailure() {
        var cleanupCallCount = 0
        let harness = makeIssueMutationFailurePresenter(
            prepareErrorPresentationSideEffects: { cleanupCallCount += 1 }
        )

        harness.presenter.presentFailure(AppError.storageFailure("Could not save."))

        XCTAssertEqual(cleanupCallCount, 1, "presentFailure must run the cleanup hook before delegating to errorPresenter.")
    }

    func testPreflightMapsCredentialTranscriptAndRecordingFailures() throws {
        let harness = try IssueExtractionControllerHarness()
        defer { harness.cleanup() }

        let session = harness.makeSession(transcript: "Transcript")
        XCTAssertEqual(
            harness.controller.preflightIssueExtraction(
                for: session,
                hasUsableAIProviderCredential: false,
                aiProviderCompatibilityIssue: nil,
                statusPhase: .idle
            ),
            .missingAPIKey
        )
        XCTAssertEqual(
            harness.controller.preflightIssueExtraction(
                for: harness.makeSession(transcript: "  \n"),
                hasUsableAIProviderCredential: true,
                aiProviderCompatibilityIssue: nil,
                statusPhase: .idle
            ),
            .emptyTranscript
        )
        XCTAssertEqual(
            harness.controller.preflightIssueExtraction(
                for: session,
                hasUsableAIProviderCredential: true,
                aiProviderCompatibilityIssue: nil,
                statusPhase: .recording
            ),
            .recordingFailure("Stop the current recording before extracting issues.")
        )
        XCTAssertEqual(
            harness.controller.preflightIssueExtraction(
                for: session,
                hasUsableAIProviderCredential: true,
                aiProviderCompatibilityIssue: "Provider unavailable.",
                statusPhase: .idle
            ),
            .transcriptionFailure("Provider unavailable.")
        )
    }

    func testExtractIssuesPersistsResultAndClearsProgress() async throws {
        let harness = try IssueExtractionControllerHarness()
        defer { harness.cleanup() }

        let session = harness.makeSession(transcript: "The save button fails.")
        try harness.transcriptStore.add(session)
        let issue = harness.makeIssue(title: "Save button fails")
        await harness.issueExtractionService.setResult(
            IssueExtractionResult(summary: "One bug.", issues: [issue])
        )

        let extraction = try await harness.controller.extractIssues(
            for: session,
            apiKey: "test-key",
            model: "gpt-test",
            apiBaseURL: URL(string: "https://api.example.test")!,
            completionLog: .manual
        )

        XCTAssertEqual(extraction.issues.map(\.title), ["Save button fails"])
        XCTAssertNil(harness.controller.issueExtractionSessionID)
        XCTAssertEqual(harness.transcriptStore.session(with: session.id)?.issueExtraction?.summary, "One bug.")
        XCTAssertEqual(harness.sessionLibrary.currentTranscript?.id, session.id)
    }

    func testUpdateExtractedIssuePersistsEditedIssue() throws {
        let harness = try IssueExtractionControllerHarness()
        defer { harness.cleanup() }

        let issue = harness.makeIssue(title: "Original title")
        let session = harness.makeSession(
            transcript: "Transcript",
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [issue])
        )
        try harness.transcriptStore.add(session)

        var updatedIssue = issue
        updatedIssue.title = "Updated title"

        XCTAssertTrue(try harness.controller.updateExtractedIssue(updatedIssue, in: session.id))
        XCTAssertEqual(
            harness.transcriptStore.session(with: session.id)?.issueExtraction?.issues.first?.title,
            "Updated title"
        )
    }

    func testSetIssueSelectionPersistsSingleIssueSelection() throws {
        let harness = try IssueExtractionControllerHarness()
        defer { harness.cleanup() }

        let issue = harness.makeIssue(title: "Selectable", isSelectedForExport: false)
        let session = harness.makeSession(
            transcript: "Transcript",
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [issue])
        )
        try harness.transcriptStore.add(session)

        XCTAssertTrue(try harness.controller.setIssueSelection(true, issueID: issue.id, in: session.id))
        XCTAssertEqual(
            harness.transcriptStore.session(with: session.id)?.issueExtraction?.issues.first?.isSelectedForExport,
            true
        )
    }

    func testSetAllIssuesSelectedPersistsBulkSelection() throws {
        let harness = try IssueExtractionControllerHarness()
        defer { harness.cleanup() }

        let firstIssue = harness.makeIssue(title: "First", isSelectedForExport: false)
        let secondIssue = harness.makeIssue(title: "Second", isSelectedForExport: true)
        let session = harness.makeSession(
            transcript: "Transcript",
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [firstIssue, secondIssue])
        )
        try harness.transcriptStore.add(session)

        XCTAssertTrue(try harness.controller.setAllIssuesSelected(false, in: session.id))
        XCTAssertEqual(
            harness.transcriptStore.session(with: session.id)?.issueExtraction?.issues.map(\.isSelectedForExport),
            [false, false]
        )
    }

    private func makeIssueMutationFailurePresenter(
        status: AppStatus = .idle(),
        prepareErrorPresentationSideEffects: @escaping () -> Void = {}
    ) -> (
        presenter: IssueMutationFailurePresenter,
        presentationState: AppPresentationState,
        telemetryRecorder: MockOperationalTelemetryRecorder
    ) {
        let presentationState = AppPresentationState(status: status)
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        let presenter = IssueMutationFailurePresenter(
            errorPresenter: AppErrorPresenter(
                presentationState: presentationState,
                telemetryRecorder: telemetryRecorder
            ),
            prepareErrorPresentationSideEffects: prepareErrorPresentationSideEffects
        )

        return (
            presenter: presenter,
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder
        )
    }

    private func makeManualIssueExtractionPresenter(
        status: AppStatus = .idle()
    ) -> (
        presenter: ManualIssueExtractionStatusPresenter,
        presentationState: AppPresentationState,
        telemetryRecorder: MockOperationalTelemetryRecorder,
        transcriptWindowOpenCount: () -> Int,
        settingsWindowOpenCount: () -> Int
    ) {
        let presentationState = AppPresentationState(status: status)
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        var transcriptWindowOpenCount = 0
        var settingsWindowOpenCount = 0
        let presenter = ManualIssueExtractionStatusPresenter(
            errorPresenter: AppErrorPresenter(
                presentationState: presentationState,
                telemetryRecorder: telemetryRecorder
            ),
            showTranscriptWindow: {
                transcriptWindowOpenCount += 1
            },
            showSettingsWindow: {
                settingsWindowOpenCount += 1
            }
        )

        return (
            presenter: presenter,
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder,
            transcriptWindowOpenCount: { transcriptWindowOpenCount },
            settingsWindowOpenCount: { settingsWindowOpenCount }
        )
    }
}

@MainActor
private final class IssueExtractionControllerHarness {
    let rootDirectoryURL: URL
    let transcriptStore: TranscriptStore
    let issueExtractionService: MockIssueExtractionService
    let sessionLibrary: SessionLibraryController
    let controller: IssueExtractionController

    init() throws {
        let fileManager = FileManager.default
        rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("BugNarratorIssueExtractionControllerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        transcriptStore = TranscriptStore(
            fileManager: fileManager,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json")
        )
        issueExtractionService = MockIssueExtractionService()
        let artifactsService = MockArtifactsService(
            rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts", isDirectory: true)
        )
        sessionLibrary = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: artifactsService,
            clipboardService: MockClipboardService()
        )
        controller = IssueExtractionController(
            sessionLibrary: sessionLibrary,
            issueExtractionService: issueExtractionService
        )
    }

    func makeSession(
        transcript: String,
        issueExtraction: IssueExtractionResult? = nil
    ) -> TranscriptSession {
        TranscriptSession(
            createdAt: Date(),
            transcript: transcript,
            duration: 6,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: issueExtraction
        )
    }

    func makeIssue(
        title: String,
        isSelectedForExport: Bool = true
    ) -> ExtractedIssue {
        ExtractedIssue(
            title: title,
            category: .bug,
            summary: "Summary for \(title)",
            evidenceExcerpt: "Evidence for \(title)",
            timestamp: 2,
            requiresReview: true,
            isSelectedForExport: isSelectedForExport
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}
