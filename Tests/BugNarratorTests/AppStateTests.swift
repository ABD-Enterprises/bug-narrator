import XCTest
@testable import BugNarrator

@MainActor
final class AppStateTests: XCTestCase {
    func testStartSessionWithoutAPIKeyShowsErrorAndOpensSettings() async {
        let harness = AppStateHarness(apiKey: "")
        defer { harness.cleanup() }

        var didOpenSettings = false
        harness.appState.showSettingsWindow = {
            didOpenSettings = true
        }

        await harness.appState.startSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(harness.appState.status.detail, AppError.missingAPIKey.userMessage)
        XCTAssertEqual(harness.audioRecorder.startCallCount, 0)
        XCTAssertTrue(didOpenSettings)
    }

    func testDuplicateStartWhileAlreadyRecordingDoesNotStartTwice() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        await harness.appState.startSession()
        await harness.appState.startSession()

        XCTAssertEqual(harness.audioRecorder.startCallCount, 1)
        XCTAssertEqual(harness.appState.status.phase, .recording)
    }

    func testStartSessionWithDeniedMicrophonePermissionFailsBeforeRecorderStarts() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.audioRecorder.permissionState = .denied

        await harness.appState.startSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(harness.appState.status.detail, AppError.microphonePermissionDenied.userMessage)
        XCTAssertEqual(harness.audioRecorder.startCallCount, 0)
    }

    func testSuccessfulSessionSavesCopiesAndDeletesTemporaryAudioFile() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "success")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "The main workflow worked.", segments: []))
        )

        await harness.appState.startSession()
        await harness.appState.stopSession()

        XCTAssertEqual(harness.appState.status.phase, .success)
        XCTAssertEqual(harness.appState.currentTranscript?.transcript, "The main workflow worked.")
        XCTAssertEqual(harness.transcriptStore.sessions.count, 1)
        XCTAssertEqual(harness.clipboardService.copiedStrings.last, "The main workflow worked.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))
        XCTAssertNil(harness.appState.activeRecordingSession)
    }

    func testTranscriptionFailureTransitionsToErrorAndDeletesTemporaryAudioFile() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "failure")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        await harness.transcriptionClient.enqueue(.failure(AppError.networkTimeout))

        await harness.appState.startSession()
        await harness.appState.stopSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(harness.appState.status.detail, AppError.networkTimeout.userMessage)
        XCTAssertEqual(harness.transcriptStore.sessions.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))
        XCTAssertNil(harness.appState.activeRecordingSession)
    }

    func testStopSessionIgnoresDuplicateStopsWhileStopping() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "duplicate-stop")
        harness.audioRecorder.suspendStop = true
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "Finished once.", segments: []))
        )

        await harness.appState.startSession()

        let firstStop = Task { @MainActor in
            await harness.appState.stopSession()
        }

        await waitUntil {
            harness.audioRecorder.stopCallCount == 1
        }

        let secondStop = Task { @MainActor in
            await harness.appState.stopSession()
        }

        await Task.yield()

        XCTAssertEqual(harness.audioRecorder.stopCallCount, 1)
        XCTAssertEqual(harness.appState.status.phase, .recording)

        harness.audioRecorder.resumeStop(with: .success(recordedAudio))

        await firstStop.value
        await secondStop.value

        let transcriptionCallCount = await harness.transcriptionClient.callCount
        XCTAssertEqual(harness.appState.status.phase, .success)
        XCTAssertEqual(transcriptionCallCount, 1)
    }

    func testCancelSessionResetsToIdleStopsTimerAndRemovesArtifacts() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        await harness.appState.startSession()
        try? await Task.sleep(for: .milliseconds(1_300))

        XCTAssertGreaterThanOrEqual(harness.appState.elapsedDuration, 1)

        await harness.appState.cancelSession()

        XCTAssertEqual(harness.appState.status.phase, .idle)
        XCTAssertEqual(harness.appState.elapsedDuration, 0)
        XCTAssertEqual(harness.audioRecorder.cancelPreserveArguments, [false])
        XCTAssertEqual(harness.artifactsService.removedDirectories.count, 1)
        XCTAssertNil(harness.appState.activeRecordingSession)
    }

    func testDebugModePreservesTemporaryAudioFileAfterSuccessfulStop() async throws {
        let harness = AppStateHarness(debugMode: true)
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "debug-success")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "Keep this file.", segments: []))
        )

        await harness.appState.startSession()
        await harness.appState.stopSession()

        XCTAssertEqual(harness.appState.status.phase, .success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))
    }

    func testStopSessionWithoutAPIKeyAfterRecordingFailsGracefully() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "missing-key-on-stop")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]

        await harness.appState.startSession()
        harness.settingsStore.removeAPIKey()
        await harness.appState.stopSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(harness.appState.status.detail, AppError.missingAPIKey.userMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))
    }

    func testValidateAPIKeyUpdatesValidationStateOnSuccess() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        await harness.appState.validateAPIKey()

        XCTAssertEqual(harness.appState.apiKeyValidationState, .success("OpenAI accepted this key."))
    }

    func testValidateAPIKeyWithoutConfiguredKeyShowsFailure() async {
        let harness = AppStateHarness(apiKey: "")
        defer { harness.cleanup() }

        await harness.appState.validateAPIKey()

        XCTAssertEqual(harness.appState.apiKeyValidationState, .failure(AppError.missingAPIKey.userMessage))
    }

    func testAboutChangelogAndSupportActionsTriggerWindowCallbacks() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        var didOpenAbout = false
        var didOpenChangelog = false
        var didOpenSupport = false
        harness.appState.showAboutWindow = {
            didOpenAbout = true
        }
        harness.appState.showChangelogWindow = {
            didOpenChangelog = true
        }
        harness.appState.showSupportWindow = {
            didOpenSupport = true
        }

        harness.appState.openAbout()
        harness.appState.openChangelog()
        harness.appState.openSupportDevelopment()

        XCTAssertTrue(didOpenAbout)
        XCTAssertTrue(didOpenChangelog)
        XCTAssertTrue(didOpenSupport)
    }

    func testProjectInfoActionsOpenExpectedURLs() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.appState.openGitHubRepository()
        harness.appState.openDocumentation()
        harness.appState.openIssueReporter()
        harness.appState.checkForUpdates()

        XCTAssertEqual(
            harness.urlHandler.openedURLs,
            [
                BugNarratorLinks.repository,
                BugNarratorLinks.documentation,
                BugNarratorLinks.issues,
                BugNarratorLinks.releases
            ]
        )
    }

    func testSupportDonationActionOpensExpectedURL() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.appState.openSupportDonationPage()

        XCTAssertEqual(
            harness.urlHandler.openedURLs,
            [BugNarratorLinks.supportDevelopment]
        )
    }

    func testProjectInfoActionFailureShowsHelpfulError() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.urlHandler.shouldSucceed = false

        harness.appState.openDocumentation()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(harness.appState.status.detail, "BugNarrator could not open the documentation.")
    }

    func testProjectInfoActionFailureDuringRecordingPreservesRecordingState() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.urlHandler.shouldSucceed = false
        await harness.appState.startSession()

        harness.appState.openDocumentation()

        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(
            harness.appState.status.detail,
            "BugNarrator could not open the documentation. Recording is still active."
        )
    }

    func testOpenScreenshotMissingFileShowsHelpfulError() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let missingScreenshot = SessionScreenshot(
            elapsedTime: 12,
            filePath: harness.rootDirectoryURL.appendingPathComponent("missing.png").path
        )

        harness.appState.openScreenshot(missingScreenshot)

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(
            harness.appState.status.detail,
            "The selected screenshot file is no longer available on this Mac."
        )
    }

    func testDeleteDisplayedTranscriptRemovesStoredSessionAndSelectsNextSession() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let artifactsDirectoryURL = harness.rootDirectoryURL.appendingPathComponent("stored-session-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsDirectoryURL, withIntermediateDirectories: true)

        let screenshotURL = artifactsDirectoryURL.appendingPathComponent("capture.png")
        try Data("screenshot".utf8).write(to: screenshotURL)

        let olderSession = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 10),
            transcript: "Older session transcript",
            duration: 12,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            screenshots: [
                SessionScreenshot(elapsedTime: 2, filePath: screenshotURL.path)
            ],
            artifactsDirectoryPath: artifactsDirectoryURL.path
        )
        let newerSession = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 20),
            transcript: "Newer session transcript",
            duration: 18,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil
        )

        try harness.transcriptStore.add(olderSession)
        try harness.transcriptStore.add(newerSession)
        harness.appState.selectedTranscriptID = olderSession.id

        harness.appState.deleteDisplayedTranscript()

        XCTAssertEqual(harness.transcriptStore.sessions.map(\.id), [newerSession.id])
        XCTAssertEqual(harness.appState.selectedTranscriptID, newerSession.id)
        XCTAssertEqual(harness.artifactsService.removedDirectories, [artifactsDirectoryURL])
        XCTAssertEqual(harness.appState.status.phase, .success)
    }

    func testInsertMarkerDuringActiveSessionStoresMarker() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        await harness.appState.startSession()
        harness.audioRecorder.currentDuration = 12

        await harness.appState.insertMarker(title: "Login flow", note: "Cursor jumped unexpectedly")

        let markers = harness.appState.activeRecordingSession?.markers ?? []
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.title, "Login flow")
        XCTAssertEqual(markers.first?.note, "Cursor jumped unexpectedly")
        XCTAssertEqual(markers.first?.elapsedTime, 12)
        XCTAssertEqual(harness.appState.status.phase, .recording)
    }

    func testInsertMarkerWithoutRecordingShowsHelpfulError() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        await harness.appState.insertMarker()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(
            harness.appState.status.detail,
            AppError.noActiveSession("Start a feedback session before inserting a marker.").userMessage
        )
    }

    func testCaptureScreenshotStoresMetadataAndAssociatesNearestMarker() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        await harness.appState.startSession()
        harness.audioRecorder.currentDuration = 10
        await harness.appState.insertMarker(title: "Checkout", note: nil)
        harness.audioRecorder.currentDuration = 12

        await harness.appState.captureScreenshot()

        let recordingSession = try XCTUnwrap(harness.appState.activeRecordingSession)
        let screenshot = try XCTUnwrap(recordingSession.screenshots.first)

        XCTAssertEqual(recordingSession.screenshots.count, 1)
        XCTAssertEqual(screenshot.elapsedTime, 12)
        XCTAssertEqual(screenshot.associatedMarkerID, recordingSession.markers.first?.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.filePath))
        XCTAssertEqual(harness.appState.status.phase, .recording)
    }

    func testCaptureScreenshotFailureKeepsRecordingAndShowsMessage() async {
        let harness = AppStateHarness(
            screenshotCaptureService: MockScreenshotCaptureService(
                error: AppError.screenshotCaptureFailure("Permission denied.")
            )
        )
        defer { harness.cleanup() }

        await harness.appState.startSession()
        await harness.appState.captureScreenshot()

        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(
            harness.appState.status.detail,
            AppError.screenshotCaptureFailure("Permission denied.").userMessage
        )
        XCTAssertEqual(harness.appState.activeRecordingSession?.screenshots.count, 0)
    }

    func testAutomaticIssueExtractionPersistsDraftIssuesAfterTranscription() async throws {
        let harness = AppStateHarness(autoExtractIssues: true)
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "auto-extract")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "The submit button clips on small windows.", segments: []))
        )
        await harness.issueExtractionService.setResult(
            IssueExtractionResult(
                summary: "One likely UX issue.",
                issues: [
                    ExtractedIssue(
                        title: "Submit button clips",
                        category: .uxIssue,
                    summary: "The submit button clips in smaller windows.",
                    evidenceExcerpt: "The submit button clips on small windows.",
                    timestamp: 4,
                        requiresReview: true
                    )
                ]
            )
        )

        await harness.appState.startSession()
        await harness.appState.stopSession()

        let session = try XCTUnwrap(harness.appState.currentTranscript)
        XCTAssertEqual(session.issueExtraction?.issues.count, 1)
        XCTAssertEqual(session.issueExtraction?.issues.first?.title, "Submit button clips")
        XCTAssertEqual(harness.appState.status.phase, .success)
    }

    func testCanExportIssuesRequiresConfiguredDestinationAndSelectedIssue() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 6,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: IssueExtractionResult(
                summary: "Summary",
                issues: [
                    ExtractedIssue(
                        title: "Issue",
                        category: .bug,
                        summary: "Summary",
                        evidenceExcerpt: "Evidence",
                        timestamp: 2,
                        requiresReview: true,
                        isSelectedForExport: true
                    )
                ]
            )
        )

        XCTAssertFalse(harness.appState.canExportIssues(from: session, to: .github))

        harness.settingsStore.githubToken = "github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"

        XCTAssertTrue(harness.appState.canExportIssues(from: session, to: .github))
    }

    func testExportSelectedIssuesFailsFastWhenConfigurationIsMissing() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 6,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: IssueExtractionResult(
                summary: "Summary",
                issues: [
                    ExtractedIssue(
                        title: "Issue",
                        category: .bug,
                        summary: "Summary",
                        evidenceExcerpt: "Evidence",
                        timestamp: 2,
                        requiresReview: true,
                        isSelectedForExport: true
                    )
                ]
            )
        )

        var didOpenSettings = false
        harness.appState.showSettingsWindow = {
            didOpenSettings = true
        }

        await harness.appState.exportSelectedIssues(from: session, to: .github)

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertTrue(didOpenSettings)
    }

    func testExportSelectedIssuesCallsGitHubProviderWhenConfigured() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        await harness.exportService.setGitHubResults([
            ExportResult(
                sourceIssueID: UUID(),
                destination: .github,
                remoteIdentifier: "#12",
                remoteURL: URL(string: "https://github.com/acme/bugnarrator/issues/12")
            )
        ])

        let sourceIssue = ExtractedIssue(
            title: "Issue",
            category: .bug,
            summary: "Summary",
            evidenceExcerpt: "Evidence",
            timestamp: 2,
            requiresReview: true,
            isSelectedForExport: true
        )
        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 6,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [sourceIssue])
        )

        await harness.appState.exportSelectedIssues(from: session, to: .github)

        let callCount = await harness.exportService.gitHubCallCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(harness.appState.status.phase, .success)
    }

    func testConsecutiveSessionsWorkBackToBackWithoutRestart() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let firstAudio = try harness.makeRecordedAudio(fileName: "first")
        let secondAudio = try harness.makeRecordedAudio(fileName: "second")
        harness.audioRecorder.stopResults = [.success(firstAudio), .success(secondAudio)]
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "First transcript", segments: []))
        )
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "Second transcript", segments: []))
        )

        await harness.appState.startSession()
        await harness.appState.stopSession()
        await harness.appState.startSession()
        await harness.appState.stopSession()

        XCTAssertEqual(harness.audioRecorder.startCallCount, 2)
        XCTAssertEqual(harness.audioRecorder.stopCallCount, 2)
        XCTAssertEqual(harness.transcriptStore.sessions.count, 2)
        XCTAssertEqual(harness.transcriptStore.sessions.first?.transcript, "Second transcript")
        XCTAssertEqual(harness.appState.status.phase, .success)
        XCTAssertNil(harness.appState.activeRecordingSession)
    }
}
