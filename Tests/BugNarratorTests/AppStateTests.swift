import XCTest
@testable import BugNarrator

@MainActor
final class AppStateTests: XCTestCase {
    func testRecordingControlsStartFlowShowsPanelAndStartsSession() async {
        let harness = AppStateHarness(apiKey: "")
        defer { harness.cleanup() }

        var didOpenRecordingControls = false
        harness.appState.showRecordingControlWindow = {
            didOpenRecordingControls = true
        }

        await harness.appState.openRecordingControlsAndStartSession()

        XCTAssertTrue(didOpenRecordingControls)
        XCTAssertEqual(harness.appState.status.phase, .recording)
    }

    func testOpenRecordingControlsShowsPanelWithoutStartingSession() {
        let harness = AppStateHarness(apiKey: "")
        defer { harness.cleanup() }

        var didOpenRecordingControls = false
        harness.appState.showRecordingControlWindow = {
            didOpenRecordingControls = true
        }

        harness.appState.openRecordingControls()

        XCTAssertTrue(didOpenRecordingControls)
        XCTAssertEqual(harness.appState.status.phase, .idle)
        XCTAssertEqual(harness.audioRecorder.startCallCount, 0)
    }

    func testStartSessionWithoutAPIKeyStillStartsRecordingAndShowsTranscriptionGuidance() async {
        let harness = AppStateHarness(apiKey: "")
        defer { harness.cleanup() }

        var didOpenSettings = false
        harness.appState.showSettingsWindow = {
            didOpenSettings = true
        }

        await harness.appState.startSession()

        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(
            harness.appState.status.detail,
            "Recording in progress. Add your OpenAI API key in Settings before stopping to transcribe this session."
        )
        XCTAssertEqual(harness.audioRecorder.startCallCount, 1)
        XCTAssertFalse(didOpenSettings)
    }

    func testAppStateRegistersDistinctRecordingHotkeys() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        XCTAssertEqual(
            harness.hotkeyManager.registeredShortcuts[.startRecording],
            harness.settingsStore.startRecordingHotkeyShortcut
        )
        XCTAssertEqual(
            harness.hotkeyManager.registeredShortcuts[.stopRecording],
            harness.settingsStore.stopRecordingHotkeyShortcut
        )
        XCTAssertEqual(
            harness.hotkeyManager.registeredShortcuts[.captureScreenshot],
            harness.settingsStore.screenshotHotkeyShortcut
        )
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
        XCTAssertEqual(harness.appState.currentError, .microphonePermissionDenied)
        XCTAssertEqual(harness.audioRecorder.startCallCount, 0)
    }

    func testStartSessionCanRecoverFromStaleDeniedPermissionWhenActivationProbeSucceeds() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.audioRecorder.permissionState = .denied
        harness.audioRecorder.activationProbeBehavior = .success

        await harness.appState.startSession()

        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertNil(harness.appState.currentError)
        XCTAssertEqual(harness.audioRecorder.startCallCount, 1)
        XCTAssertEqual(harness.audioRecorder.activationProbeCallCount, 1)
    }

    func testStartSessionWithRestrictedMicrophonePermissionFailsBeforeRecorderStarts() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.audioRecorder.permissionState = .restricted

        await harness.appState.startSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(harness.appState.currentError, .microphonePermissionRestricted)
        XCTAssertEqual(harness.audioRecorder.startCallCount, 0)
    }

    func testStartSessionRequestsMicrophonePermissionBeforeRecording() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.audioRecorder.permissionState = .notDetermined
        harness.audioRecorder.requestedPermissionStates = [.authorized]

        await harness.appState.startSession()

        XCTAssertEqual(harness.audioRecorder.permissionRequestCallCount, 1)
        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(harness.audioRecorder.startCallCount, 1)
    }

    func testStartSessionShowsCaptureUnavailableErrorWhenPrerequisitesFail() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.audioRecorder.prerequisiteError = .microphoneUnavailable("The selected microphone could not be opened.")

        await harness.appState.startSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(
            harness.appState.currentError,
            .microphoneUnavailable("The selected microphone could not be opened.")
        )
        XCTAssertEqual(harness.audioRecorder.startCallCount, 0)
    }

    func testPermissionRefreshClearsStaleMicrophoneDeniedErrorAfterAccessIsGranted() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.audioRecorder.permissionState = .denied

        await harness.appState.startSession()

        XCTAssertEqual(harness.appState.currentError, .microphonePermissionDenied)
        XCTAssertEqual(harness.appState.status.phase, .error)

        harness.audioRecorder.permissionState = .authorized
        harness.appState.refreshPermissionRecoveryState()

        XCTAssertNil(harness.appState.currentError)
        XCTAssertEqual(harness.appState.status.phase, .idle)
        XCTAssertEqual(
            harness.appState.status.detail,
            "Microphone access enabled. You can start recording again."
        )
    }

    func testPermissionRefreshClearsStaleMicrophoneRestrictedErrorAfterAccessIsGranted() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.audioRecorder.permissionState = .restricted

        await harness.appState.startSession()

        XCTAssertEqual(harness.appState.currentError, .microphonePermissionRestricted)

        harness.audioRecorder.permissionState = .authorized
        harness.appState.refreshPermissionRecoveryState()

        XCTAssertNil(harness.appState.currentError)
        XCTAssertEqual(harness.appState.status.phase, .idle)
    }

    func testPermissionRefreshClearsStaleScreenRecordingDeniedErrorAfterAccessIsGranted() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.screenCapturePermissionAccess.permissionState = .denied

        await harness.appState.startSession()
        await harness.appState.captureScreenshot()

        XCTAssertEqual(harness.appState.currentError, .screenRecordingPermissionDenied)
        XCTAssertEqual(harness.appState.status.phase, .recording)

        harness.screenCapturePermissionAccess.permissionState = .granted
        harness.appState.refreshPermissionRecoveryState()

        XCTAssertNil(harness.appState.currentError)
        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(
            harness.appState.status.detail,
            "Screen Recording access enabled. You can capture screenshots again."
        )
    }

    func testLocalTestingBuildAddsMicrophoneRecoveryGuidance() {
        let harness = AppStateHarness(
            runtimeEnvironment: AppRuntimeEnvironment(
                bundlePath: "/Users/deffenda/Library/Developer/Xcode/DerivedData/BugNarrator/Build/Products/Debug/BugNarrator.app"
            )
        )
        defer { harness.cleanup() }

        harness.audioRecorder.permissionState = .denied

        XCTAssertTrue(harness.appState.microphoneRecoveryGuidance.contains("System Settings > Privacy & Security > Microphone"))
        XCTAssertEqual(
            harness.appState.microphoneRecoveryLocalTestingNote,
            "Local unsigned builds can need microphone approval again if you switch to a different app copy or rebuild into a new path. If System Settings already shows BugNarrator enabled, quit any other BugNarrator copies and retest the same app bundle path or the signed DMG build."
        )
    }

    func testOpenMicrophoneSettingsUsesPrivacyDeepLinkFirst() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.appState.openMicrophonePrivacySettings()

        XCTAssertEqual(harness.urlHandler.openedURLs, [BugNarratorLinks.microphonePrivacySettings])
    }

    func testOpenMicrophoneSettingsFallsBackToSecuritySettings() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.urlHandler.openResults = [false, true]

        harness.appState.openMicrophonePrivacySettings()

        XCTAssertEqual(
            harness.urlHandler.openedURLs,
            [
                BugNarratorLinks.microphonePrivacySettings,
                BugNarratorLinks.securityPrivacySettings
            ]
        )
    }

    func testOpenScreenRecordingSettingsUsesPrivacyDeepLinkFirst() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.appState.openScreenRecordingPrivacySettings()

        XCTAssertEqual(harness.urlHandler.openedURLs, [BugNarratorLinks.screenRecordingPrivacySettings])
    }

    func testOpenScreenRecordingSettingsFallsBackToSecuritySettings() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.urlHandler.openResults = [false, true]

        harness.appState.openScreenRecordingPrivacySettings()

        XCTAssertEqual(
            harness.urlHandler.openedURLs,
            [
                BugNarratorLinks.screenRecordingPrivacySettings,
                BugNarratorLinks.securityPrivacySettings
            ]
        )
    }

    func testCopyDebugInfoCopiesSafeSupportMetadataToClipboard() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let session = TranscriptSession(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            createdAt: Date(),
            transcript: "A saved transcript.",
            duration: 12,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil
        )
        try harness.transcriptStore.add(session)
        harness.appState.selectedTranscriptID = session.id

        harness.appState.copyDebugInfo()

        let copied = try XCTUnwrap(harness.clipboardService.copiedStrings.last)
        XCTAssertTrue(copied.contains("BugNarrator Version"))
        XCTAssertTrue(copied.contains("Transcription Model: whisper-1"))
        XCTAssertTrue(copied.contains("Issue Extraction Model: gpt-4.1-mini"))
        XCTAssertTrue(copied.contains("Session ID: \(session.id.uuidString)"))
        XCTAssertFalse(copied.contains(harness.settingsStore.trimmedAPIKey))
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

    func testSuccessfulTranscriptionWithStorageFailureKeepsTranscriptAvailableForManualSave() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "storage-failure")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "Transcript survived local save failure.", segments: []))
        )

        var didOpenTranscriptWindow = false
        harness.appState.showTranscriptWindow = {
            didOpenTranscriptWindow = true
        }

        await harness.appState.startSession()
        await harness.appState.captureScreenshot()

        let storageURL = harness.rootDirectoryURL.appendingPathComponent("sessions.json")
        try? FileManager.default.removeItem(at: storageURL)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

        await harness.appState.stopSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertTrue(
            harness.appState.status.detail?.hasPrefix("Transcript ready, but Could not save local session history:") == true
        )
        XCTAssertEqual(harness.appState.currentTranscript?.transcript, "Transcript survived local save failure.")
        XCTAssertFalse(harness.appState.currentTranscriptIsPersisted)
        XCTAssertEqual(harness.transcriptStore.sessions.count, 0)
        XCTAssertEqual(harness.clipboardService.copiedStrings.last, "Transcript survived local save failure.")
        XCTAssertTrue(didOpenTranscriptWindow)
        XCTAssertNil(harness.appState.activeRecordingSession)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))

        let screenshotPath = try XCTUnwrap(harness.appState.currentTranscript?.screenshots.first?.filePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotPath))
        XCTAssertTrue(harness.artifactsService.removedDirectories.isEmpty)
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

    func testCaptureScreenshotStoresMetadataAndCreatesAutoMarker() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        await harness.appState.startSession()
        harness.audioRecorder.currentDuration = 12

        await harness.appState.captureScreenshot()

        let recordingSession = try XCTUnwrap(harness.appState.activeRecordingSession)
        let screenshot = try XCTUnwrap(recordingSession.screenshots.first)
        let autoMarker = try XCTUnwrap(recordingSession.markers.last)

        XCTAssertEqual(recordingSession.screenshots.count, 1)
        XCTAssertEqual(recordingSession.markers.count, 1)
        XCTAssertEqual(screenshot.elapsedTime, 12)
        XCTAssertEqual(screenshot.associatedMarkerID, autoMarker.id)
        XCTAssertEqual(autoMarker.title, "Screenshot 1")
        XCTAssertNil(autoMarker.note)
        XCTAssertEqual(autoMarker.screenshotID, screenshot.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.filePath))
        XCTAssertEqual(harness.screenshotSelectionService.selectRegionCallCount, 1)
        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(harness.appState.status.detail, "Captured Screenshot 1.")
        XCTAssertEqual(harness.appState.transientToast?.message, "Screenshot captured")
    }

    func testCaptureScreenshotCancellationKeepsRecordingWithoutCreatingMarkerOrScreenshot() async {
        let selectionService = MockScreenshotSelectionService()
        selectionService.nextResult = .cancelled
        let harness = AppStateHarness(screenshotSelectionService: selectionService)
        defer { harness.cleanup() }

        await harness.appState.startSession()
        await harness.appState.captureScreenshot()

        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(harness.appState.status.detail, "Recording in progress.")
        XCTAssertNil(harness.appState.currentError)
        XCTAssertEqual(harness.appState.activeRecordingSession?.screenshots.count, 0)
        XCTAssertEqual(harness.appState.activeRecordingSession?.markers.count, 0)
        XCTAssertEqual(harness.appState.transientToast?.message, "Screenshot canceled")
    }

    func testCaptureScreenshotFailureKeepsRecordingAndShowsMessage() async {
        let harness = AppStateHarness(
            screenshotCaptureService: MockScreenshotCaptureService(
                error: AppError.screenshotCaptureFailure("The screenshot file could not be written to disk.")
            )
        )
        defer { harness.cleanup() }

        await harness.appState.startSession()
        await harness.appState.captureScreenshot()

        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(
            harness.appState.status.detail,
            AppError.screenshotCaptureFailure("The screenshot file could not be written to disk.").userMessage
        )
        XCTAssertEqual(
            harness.appState.currentError,
            AppError.screenshotCaptureFailure("The screenshot file could not be written to disk.")
        )
        XCTAssertEqual(harness.appState.activeRecordingSession?.screenshots.count, 0)
        XCTAssertEqual(harness.appState.activeRecordingSession?.markers.count, 0)
    }

    func testCaptureScreenshotWithDeniedScreenRecordingKeepsRecordingAndShowsRecoveryContext() async {
        var didAttemptCapture = false
        let screenshotService = MockScreenshotCaptureService(onCaptureStart: {
            didAttemptCapture = true
        })
        let harness = AppStateHarness(screenshotCaptureService: screenshotService)
        defer { harness.cleanup() }

        harness.screenCapturePermissionAccess.permissionState = .denied
        await harness.appState.startSession()
        await harness.appState.captureScreenshot()

        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(harness.appState.status.detail, AppError.screenRecordingPermissionDenied.userMessage)
        XCTAssertEqual(harness.appState.currentError, .screenRecordingPermissionDenied)
        XCTAssertEqual(harness.appState.activeRecordingSession?.screenshots.count, 0)
        XCTAssertEqual(harness.appState.activeRecordingSession?.markers.count, 0)
        XCTAssertFalse(didAttemptCapture)
    }

    func testRapidRepeatedScreenshotRequestsOnlyPersistOneCaptureAtATime() async throws {
        let firstCaptureStarted = expectation(description: "first screenshot capture started")
        let screenshotService = MockScreenshotCaptureService(delayNanoseconds: 200_000_000)
        screenshotService.onCaptureStart = {
            firstCaptureStarted.fulfill()
        }

        let harness = AppStateHarness(screenshotCaptureService: screenshotService)
        defer { harness.cleanup() }

        await harness.appState.startSession()

        async let firstCapture: Void = harness.appState.captureScreenshot()
        await fulfillment(of: [firstCaptureStarted], timeout: 1.0)
        async let secondCapture: Void = harness.appState.captureScreenshot()
        _ = await (firstCapture, secondCapture)

        let recordingSession = try XCTUnwrap(harness.appState.activeRecordingSession)
        XCTAssertEqual(recordingSession.screenshots.count, 1)
        XCTAssertEqual(recordingSession.markers.count, 1)
        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(harness.appState.status.detail, "Captured Screenshot 1.")
        XCTAssertNil(harness.appState.currentError)
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

    func testExtractIssuesWithoutAPIKeyFailsAndOpensSettings() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 6,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil
        )
        try harness.transcriptStore.add(session)
        harness.appState.selectedTranscriptID = session.id
        harness.settingsStore.removeAPIKey()

        var didOpenSettings = false
        harness.appState.showSettingsWindow = {
            didOpenSettings = true
        }

        await harness.appState.extractIssuesForDisplayedTranscript()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(harness.appState.status.detail, AppError.missingAPIKey.userMessage)
        XCTAssertTrue(didOpenSettings)
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
        XCTAssertNoThrow(try harness.transcriptStore.add(session))
        harness.appState.selectedTranscriptID = session.id

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
        XCTAssertNoThrow(try harness.transcriptStore.add(session))
        harness.appState.selectedTranscriptID = session.id

        var didOpenSettings = false
        harness.appState.showSettingsWindow = {
            didOpenSettings = true
        }

        await harness.appState.exportSelectedIssues(from: session, to: .github)

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertTrue(didOpenSettings)
    }

    func testExportSelectedIssuesFailsWhenSessionIsNoLongerAvailable() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"

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

        await harness.appState.exportSelectedIssues(from: session, to: .github)

        let callCount = await harness.exportService.gitHubCallCount
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(
            harness.appState.status.detail,
            AppError.exportFailure("This session is no longer available in the library.").userMessage
        )
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
        XCTAssertNoThrow(try harness.transcriptStore.add(session))
        harness.appState.selectedTranscriptID = session.id

        await harness.appState.exportSelectedIssues(from: session, to: .github)

        let callCount = await harness.exportService.gitHubCallCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(harness.appState.status.phase, .success)
    }

    func testPersistUpdatedSessionFailureKeepsEditedIssueVisibleAsUnsavedOverlay() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let originalIssue = ExtractedIssue(
            title: "Original title",
            category: .bug,
            summary: "Summary",
            evidenceExcerpt: "Evidence",
            timestamp: 5,
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
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [originalIssue])
        )
        try harness.transcriptStore.add(session)
        harness.appState.selectedTranscriptID = session.id

        let storageURL = harness.rootDirectoryURL.appendingPathComponent("sessions.json")
        try FileManager.default.removeItem(at: storageURL)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

        var updatedIssue = originalIssue
        updatedIssue.title = "Updated visible title"

        harness.appState.updateExtractedIssue(updatedIssue, in: session.id)

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertTrue(
            harness.appState.status.detail?.hasPrefix("Could not save local session history:") == true
        )
        XCTAssertEqual(
            harness.appState.currentTranscript?.issueExtraction?.issues.first?.title,
            "Updated visible title"
        )
        XCTAssertEqual(
            harness.appState.displayedTranscript?.issueExtraction?.issues.first?.title,
            "Updated visible title"
        )
        XCTAssertFalse(harness.appState.currentTranscriptIsPersisted)
        XCTAssertEqual(
            harness.transcriptStore.session(with: session.id)?.issueExtraction?.issues.first?.title,
            "Original title"
        )
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
