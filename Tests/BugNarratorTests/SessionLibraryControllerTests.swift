import XCTest
@testable import BugNarrator

@MainActor
final class SessionLibraryControllerTests: XCTestCase {
    func testSelectAndRefreshSelectionAfterMissingStoredSessionFallsBackToLatest() throws {
        let harness = try SessionLibraryControllerHarness()
        defer { harness.cleanup() }

        let older = makeSession(index: 1)
        let newer = makeSession(index: 2)
        try harness.transcriptStore.add(older)
        try harness.transcriptStore.add(newer)

        harness.controller.selectedTranscriptID = older.id
        XCTAssertEqual(harness.controller.displayedTranscript?.id, older.id)

        _ = try harness.transcriptStore.removeSessions(withIDs: [older.id])
        harness.controller.refreshSelectionAfterLibraryReload()

        XCTAssertEqual(harness.controller.selectedTranscriptID, newer.id)
        XCTAssertEqual(harness.controller.displayedTranscript?.id, newer.id)
    }

    func testSaveCurrentTranscriptPersistsAndSelectsCurrentTranscript() throws {
        let harness = try SessionLibraryControllerHarness()
        defer { harness.cleanup() }

        let unsaved = makeSession(index: 1)
        harness.controller.stageCurrentTranscript(unsaved)

        let saved = try harness.controller.saveCurrentTranscriptToHistory()

        XCTAssertEqual(saved?.id, unsaved.id)
        XCTAssertEqual(harness.transcriptStore.session(with: unsaved.id), unsaved)
        XCTAssertEqual(harness.controller.selectedTranscriptID, unsaved.id)
        XCTAssertTrue(harness.controller.currentTranscriptIsPersisted)
    }

    func testDeleteSessionsRemovesStoredSessionCleansArtifactsAndSelectsNextSession() throws {
        let harness = try SessionLibraryControllerHarness()
        defer { harness.cleanup() }

        let older = makeSession(index: 1)
        let artifactsDirectoryURL = harness.rootDirectoryURL.appendingPathComponent("session-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsDirectoryURL, withIntermediateDirectories: true)
        let newer = makeSession(index: 2, artifactsDirectoryPath: artifactsDirectoryURL.path)
        try harness.transcriptStore.add(older)
        try harness.transcriptStore.add(newer)
        harness.controller.selectedTranscriptID = newer.id

        let deletedCount = try harness.controller.deleteSessions(withIDs: [newer.id])

        XCTAssertEqual(deletedCount, 1)
        XCTAssertNil(harness.transcriptStore.session(with: newer.id))
        XCTAssertEqual(harness.controller.selectedTranscriptID, older.id)
        XCTAssertEqual(harness.artifactsService.removedDirectories, [artifactsDirectoryURL])
    }

    func testPersistUpdatedSessionUpdatesStoredSessionAndCurrentTranscript() throws {
        let harness = try SessionLibraryControllerHarness()
        defer { harness.cleanup() }

        var session = makeSession(index: 1)
        try harness.transcriptStore.add(session)
        session.issueExtraction = IssueExtractionResult(
            summary: "Updated summary",
            issues: [
                ExtractedIssue(
                    title: "Updated issue",
                    category: .bug,
                    summary: "Summary",
                    evidenceExcerpt: "Evidence",
                    timestamp: 4
                )
            ]
        )

        try harness.controller.persistUpdatedSession(session, updatedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(
            harness.transcriptStore.session(with: session.id)?.issueExtraction?.summary,
            "Updated summary"
        )
        XCTAssertEqual(harness.controller.currentTranscript?.issueExtraction?.issues.first?.title, "Updated issue")
        XCTAssertEqual(harness.controller.selectedTranscriptID, session.id)
    }

    func testDeleteDisplayedTranscriptDeletesUnsavedCurrentAndFallsBackToStoredSelection() throws {
        let harness = try SessionLibraryControllerHarness()
        defer { harness.cleanup() }

        let stored = makeSession(index: 1)
        try harness.transcriptStore.add(stored)

        let artifactsDirectoryURL = harness.rootDirectoryURL.appendingPathComponent("unsaved-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsDirectoryURL, withIntermediateDirectories: true)
        let unsaved = makeSession(index: 2, artifactsDirectoryPath: artifactsDirectoryURL.path)
        harness.controller.stageCurrentTranscript(unsaved)

        let deletedCount = try harness.controller.deleteDisplayedTranscript()

        XCTAssertEqual(deletedCount, 1)
        XCTAssertNil(harness.controller.currentTranscript)
        XCTAssertEqual(harness.controller.selectedTranscriptID, stored.id)
        XCTAssertEqual(harness.controller.displayedTranscript?.id, stored.id)
        XCTAssertEqual(harness.artifactsService.removedDirectories, [artifactsDirectoryURL])
    }

    func testSessionDeletionStatusPresenterMapsDeletedCounts() {
        XCTAssertNil(SessionDeletionStatusPresenter.status(deletedCount: 0))
        XCTAssertEqual(
            SessionDeletionStatusPresenter.status(deletedCount: 1),
            .success("Deleted 1 session.")
        )
        XCTAssertEqual(
            SessionDeletionStatusPresenter.status(deletedCount: 3),
            .success("Deleted 3 sessions.")
        )
    }

    func testDisplayedTranscriptCopyStatusPresenterMapsResults() {
        XCTAssertNil(DisplayedTranscriptCopyStatusPresenter.status(for: .noDisplayedTranscript))
        XCTAssertEqual(
            DisplayedTranscriptCopyStatusPresenter.status(for: .transcriptUnavailable),
            .error("Transcription is not available yet. Retry the preserved session first.")
        )
        XCTAssertEqual(
            DisplayedTranscriptCopyStatusPresenter.status(for: .copied),
            .success("Transcript copied to the clipboard.")
        )
    }

    func testTranscriptSaveStatusPresenterMapsResults() {
        XCTAssertNil(TranscriptSaveStatusPresenter.status(savedSession: nil))
        XCTAssertEqual(
            TranscriptSaveStatusPresenter.status(savedSession: makeSession(index: 1)),
            .success("Transcript saved to session history.")
        )
    }

    func testSessionLibraryStatusPresenterSetsCopiedTranscriptStatus() {
        let harness = makeSessionLibraryStatusPresenter()

        harness.presenter.presentDisplayedTranscriptCopyResult(.copied)

        XCTAssertEqual(harness.presentationState.status, .success("Transcript copied to the clipboard."))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testSessionLibraryStatusPresenterSetsUnavailableTranscriptStatus() {
        let harness = makeSessionLibraryStatusPresenter()

        harness.presenter.presentDisplayedTranscriptCopyResult(.transcriptUnavailable)

        XCTAssertEqual(
            harness.presentationState.status,
            .error("Transcription is not available yet. Retry the preserved session first.")
        )
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testSessionLibraryStatusPresenterLeavesStatusForMissingDisplayedTranscript() {
        let harness = makeSessionLibraryStatusPresenter(status: .idle("Ready."))

        harness.presenter.presentDisplayedTranscriptCopyResult(.noDisplayedTranscript)

        XCTAssertEqual(harness.presentationState.status, .idle("Ready."))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testSessionLibraryStatusPresenterSetsSavedTranscriptStatus() {
        let harness = makeSessionLibraryStatusPresenter()

        harness.presenter.presentSavedSession(makeSession(index: 1))

        XCTAssertEqual(harness.presentationState.status, .success("Transcript saved to session history."))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testSessionLibraryStatusPresenterLeavesStatusForNoSavedTranscript() {
        let harness = makeSessionLibraryStatusPresenter(status: .idle("Ready."))

        harness.presenter.presentSavedSession(nil)

        XCTAssertEqual(harness.presentationState.status, .idle("Ready."))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testSessionLibraryStatusPresenterSetsDeletionStatus() {
        let harness = makeSessionLibraryStatusPresenter()

        harness.presenter.presentDeletedCount(3)

        XCTAssertEqual(harness.presentationState.status, .success("Deleted 3 sessions."))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testSessionLibraryStatusPresenterLeavesStatusForNoDeletedSessions() {
        let harness = makeSessionLibraryStatusPresenter(status: .idle("Ready."))

        harness.presenter.presentDeletedCount(0)

        XCTAssertEqual(harness.presentationState.status, .idle("Ready."))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testSessionLibraryStatusPresenterNormalizesFailures() {
        let harness = makeSessionLibraryStatusPresenter()
        let error = NSError(
            domain: "BugNarratorTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Disk full"]
        )
        let expectedError = AppError.storageFailure("Disk full")

        harness.presenter.presentFailure(error)

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata["operation"], "session_library")
    }

    func testPersistCompletedTranscriptCopiesWhenRequested() throws {
        let harness = try SessionLibraryControllerHarness()
        defer { harness.cleanup() }

        let session = makeSession(index: 1, transcript: "Copy me")

        try harness.controller.persistCompletedTranscript(session, autoCopyTranscript: true)

        XCTAssertEqual(harness.transcriptStore.session(with: session.id), session)
        XCTAssertEqual(harness.controller.selectedTranscriptID, session.id)
        XCTAssertEqual(harness.clipboardService.copiedStrings, ["Copy me"])
    }

    func testStageCurrentTranscriptCopiesWhenRequested() throws {
        let harness = try SessionLibraryControllerHarness()
        defer { harness.cleanup() }

        let session = makeSession(index: 1, transcript: "Recovered transcript")

        harness.controller.stageCurrentTranscript(session, autoCopyTranscript: true)

        XCTAssertEqual(harness.controller.currentTranscript?.id, session.id)
        XCTAssertEqual(harness.controller.selectedTranscriptID, session.id)
        XCTAssertEqual(harness.clipboardService.copiedStrings, ["Recovered transcript"])
    }

    func testPersistUpdatedSessionCopiesWhenRequested() throws {
        let harness = try SessionLibraryControllerHarness()
        defer { harness.cleanup() }

        let session = makeSession(index: 1, transcript: "Retried transcript")
        try harness.transcriptStore.add(session)

        try harness.controller.persistUpdatedSession(session, autoCopyTranscript: true)

        XCTAssertEqual(harness.controller.currentTranscript?.id, session.id)
        XCTAssertEqual(harness.controller.selectedTranscriptID, session.id)
        XCTAssertEqual(harness.clipboardService.copiedStrings, ["Retried transcript"])
    }

    func testCopyDisplayedTranscriptWithoutDisplayedTranscriptDoesNothing() throws {
        let harness = try SessionLibraryControllerHarness()
        defer { harness.cleanup() }

        let result = harness.controller.copyDisplayedTranscript()

        XCTAssertEqual(result, .noDisplayedTranscript)
        XCTAssertTrue(harness.clipboardService.copiedStrings.isEmpty)
    }

    func testCopyDisplayedTranscriptWithoutTranscriptContentReturnsUnavailable() throws {
        let harness = try SessionLibraryControllerHarness()
        defer { harness.cleanup() }

        let pendingSession = makeSession(
            index: 1,
            transcript: "   ",
            pendingTranscription: PendingTranscription(
                audioFileName: "recording.m4a",
                failureReason: .missingAPIKey,
                preservedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try harness.transcriptStore.add(pendingSession)
        harness.controller.selectedTranscriptID = pendingSession.id

        let result = harness.controller.copyDisplayedTranscript()

        XCTAssertEqual(result, .transcriptUnavailable)
        XCTAssertTrue(harness.clipboardService.copiedStrings.isEmpty)
    }

    func testCopyDisplayedTranscriptCopiesDisplayedTranscript() throws {
        let harness = try SessionLibraryControllerHarness()
        defer { harness.cleanup() }

        let older = makeSession(index: 1, transcript: "Older transcript")
        let displayed = makeSession(index: 2, transcript: "Displayed transcript")
        try harness.transcriptStore.add(older)
        try harness.transcriptStore.add(displayed)
        harness.controller.selectedTranscriptID = displayed.id

        let result = harness.controller.copyDisplayedTranscript()

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(harness.clipboardService.copiedStrings, ["Displayed transcript"])
    }

    private func makeSessionLibraryStatusPresenter(
        status: AppStatus = .idle()
    ) -> (
        presenter: SessionLibraryStatusPresenter,
        presentationState: AppPresentationState,
        telemetryRecorder: MockOperationalTelemetryRecorder
    ) {
        let presentationState = AppPresentationState(status: status)
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        let presenter = SessionLibraryStatusPresenter(
            errorPresenter: AppErrorPresenter(
                presentationState: presentationState,
                telemetryRecorder: telemetryRecorder
            )
        )

        return (
            presenter: presenter,
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder
        )
    }

    private func makeSession(
        index: Int,
        transcript: String? = nil,
        pendingTranscription: PendingTranscription? = nil,
        artifactsDirectoryPath: String? = nil
    ) -> TranscriptSession {
        TranscriptSession(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            transcript: transcript ?? "Transcript \(index)",
            duration: TimeInterval(index),
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            pendingTranscription: pendingTranscription,
            artifactsDirectoryPath: artifactsDirectoryPath
        )
    }
}

@MainActor
private struct SessionLibraryControllerHarness {
    let rootDirectoryURL: URL
    let transcriptStore: TranscriptStore
    let artifactsService: MockArtifactsService
    let clipboardService: MockClipboardService
    let controller: SessionLibraryController

    init() throws {
        rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionLibraryControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        transcriptStore = TranscriptStore(
            fileManager: .default,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json")
        )
        artifactsService = MockArtifactsService(
            rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts", isDirectory: true)
        )
        clipboardService = MockClipboardService()
        controller = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: artifactsService,
            clipboardService: clipboardService
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}
