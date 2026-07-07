import AppKit
import Combine
import XCTest
@testable import BugNarrator

@MainActor
final class AppStateTests: XCTestCase {
    func testPresentationStateBacksAppStateStatusErrorAndToastFacade() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        var appStateChangeCount = 0
        let cancellable = harness.appState.objectWillChange.sink {
            appStateChangeCount += 1
        }
        defer { cancellable.cancel() }

        harness.appState.presentationState.setStatus(.error("Needs attention"), error: .missingAPIKey)
        harness.appState.presentationState.showToast(TransientToast(message: "Saved", style: .success))

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(harness.appState.status.detail, "Needs attention")
        XCTAssertEqual(harness.appState.currentError, .missingAPIKey)
        XCTAssertEqual(harness.appState.transientToast?.message, "Saved")
        XCTAssertGreaterThanOrEqual(appStateChangeCount, 2)
    }

    func testSettingsStoreChangesInvalidateMenuFacingSetupState() {
        let harness = AppStateHarness(apiKey: "")
        defer { harness.cleanup() }

        XCTAssertTrue(harness.appState.needsAPIKeySetup)

        var appStateChangeCount = 0
        let cancellable = harness.appState.objectWillChange.sink {
            appStateChangeCount += 1
        }
        defer { cancellable.cancel() }

        harness.settingsStore.apiKey = "fixture-openai-key"

        XCTAssertFalse(harness.appState.needsAPIKeySetup)
        XCTAssertGreaterThanOrEqual(appStateChangeCount, 1)
    }

    func testRecordingControlsStartFlowShowsPanelAndStartsSession() async {
        let harness = AppStateHarness()
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

    func testOpenSettingsDoesNotForceInteractiveSecretRefresh() {
        let harness = AppStateHarness(apiKey: "")
        defer { harness.cleanup() }

        var didOpenSettings = false
        harness.appState.showSettingsWindow = {
            didOpenSettings = true
        }

        harness.appState.openSettings()

        XCTAssertTrue(didOpenSettings)
        XCTAssertFalse(
            harness.keychainService.readRequests.contains {
                $0.allowInteraction
            }
        )
    }

    func testRefreshExportHistoryLoadsReceiptsForReviewSurface() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let receipt = ExportReceipt(
            fingerprint: "github:fixture",
            sourceIssueID: UUID(),
            destination: .github,
            targetIdentity: "ABD-Enterprises/bug-narrator",
            state: .succeeded,
            remoteIdentifier: "#42",
            remoteURL: URL(string: "https://github.com/ABD-Enterprises/bug-narrator/issues/42"),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        await harness.exportService.setExportReceipts([receipt])

        await harness.appState.refreshExportHistory()

        XCTAssertEqual(harness.appState.exportHistory, [receipt])
    }

    func testStartSessionWithoutAPIKeyBlocksRecordingAndOpensSettings() async {
        let harness = AppStateHarness(apiKey: "")
        defer { harness.cleanup() }

        var didOpenSettings = false
        harness.appState.showSettingsWindow = {
            didOpenSettings = true
        }

        await harness.appState.startSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(
            harness.appState.status.detail,
            "BugNarrator requires your own OpenAI API key for transcription and issue extraction. Add it in Settings, then retry transcription."
        )
        XCTAssertEqual(harness.appState.currentError, .missingAPIKey)
        XCTAssertEqual(harness.audioRecorder.startCallCount, 0)
        XCTAssertTrue(didOpenSettings)
    }

    func testStartSessionWithProviderCompatibilityIssueBlocksRecordingAndOpensSettings() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.aiProvider = .localCompatible
        harness.settingsStore.preferredModel = "whisper-1"
        var didOpenSettings = false
        harness.appState.showSettingsWindow = {
            didOpenSettings = true
        }

        await harness.appState.startSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(
            harness.appState.status.detail,
            "Choose a local transcription model instead of whisper-1 for the Local-Compatible provider."
        )
        XCTAssertEqual(harness.audioRecorder.startCallCount, 0)
        XCTAssertTrue(didOpenSettings)
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

    func testAppStateUpdatesRegisteredHotkeysWhenSettingsChange() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let updatedShortcut = HotkeyShortcut(
            keyCode: 7,
            modifiers: NSEvent.ModifierFlags.command.union(.option).rawValue
        )

        harness.settingsStore.startRecordingHotkeyShortcut = updatedShortcut

        XCTAssertEqual(harness.hotkeyManager.registeredShortcuts[.startRecording], updatedShortcut)
    }

    func testApplicationTerminationUnregistersHotkeys() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        XCTAssertFalse(harness.hotkeyManager.registeredShortcuts.isEmpty)

        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)

        XCTAssertTrue(harness.hotkeyManager.registeredShortcuts.isEmpty)
    }

    func testApplicationShouldTerminateAllowsQuitWhenNotRecording() {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        XCTAssertEqual(harness.appState.applicationShouldTerminate(), .terminateNow)
    }

    func testApplicationShouldTerminateCancelsQuitWhileRecording() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        var didOpenRecordingControls = false
        harness.appState.showRecordingControlWindow = {
            didOpenRecordingControls = true
        }

        await harness.appState.startSession()

        let reply = harness.appState.applicationShouldTerminate()

        XCTAssertEqual(reply, .terminateCancel)
        XCTAssertTrue(didOpenRecordingControls)
        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(harness.appState.transientToast?.message, "Stop recording before quitting BugNarrator.")
    }

    func testDuplicateStartWhileAlreadyRecordingDoesNotStartTwice() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        await harness.appState.startSession()
        let activeSessionID = harness.appState.activeRecordingSession?.sessionID
        await harness.appState.startSession()

        XCTAssertEqual(harness.audioRecorder.startCallCount, 1)
        XCTAssertEqual(harness.appState.status.phase, .recording)
        XCTAssertEqual(harness.appState.activeRecordingSession?.sessionID, activeSessionID)
        XCTAssertTrue(harness.artifactsService.removedDirectories.isEmpty)
    }

    func testActiveRecordingSessionStatusIsScopedToActiveDraftOnly() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let savedSession = makeSampleTranscriptSession(index: 1)
        try harness.transcriptStore.add(savedSession)

        await harness.appState.startSession()

        let activeSessionID = try XCTUnwrap(harness.appState.activeRecordingSession?.sessionID)
        XCTAssertTrue(harness.appState.isActiveRecordingSession(activeSessionID))
        XCTAssertFalse(harness.appState.isActiveRecordingSession(savedSession.id))
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

    func testStartSessionDoesNotStartWhenPermissionLooksDeniedEvenIfProbeWouldSucceed() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.audioRecorder.permissionState = .denied
        harness.audioRecorder.activationProbeBehavior = .success

        await harness.appState.startSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(harness.appState.currentError, .microphonePermissionDenied)
        XCTAssertEqual(harness.audioRecorder.startCallCount, 0)
        XCTAssertEqual(harness.audioRecorder.activationProbeCallCount, 0)
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

    func testDeleteAllLocalDataUsesInjectedPrivacyDataManager() async {
        let localPrivacyDataManager = MockLocalPrivacyDataManager()
        let harness = AppStateHarness(localPrivacyDataManager: localPrivacyDataManager)
        defer { harness.cleanup() }

        await harness.appState.deleteAllLocalData()

        XCTAssertEqual(localPrivacyDataManager.clearCallCount, 1)
        XCTAssertEqual(harness.appState.status.phase, .success)
        XCTAssertEqual(
            harness.appState.status.detail,
            "Cleared local diagnostics and export history."
        )
    }

    func testPrivacyDataExportFailureUsesStableFallbackAndPreservesUnderlyingDiagnostics() async throws {
        let privacyDataExporter = MockPrivacyDataExporter()
        privacyDataExporter.exportResult = .failure(makeFixtureError("temporary export directory is unavailable"))
        let harness = AppStateHarness(privacyDataExporter: privacyDataExporter)
        defer { harness.cleanup() }

        await harness.appState.exportPrivacyData()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(
            harness.appState.status.detail,
            AppError.exportFailure("BugNarrator could not create the data export.").userMessage
        )

        let event = try lastAppErrorTelemetry(in: harness)
        XCTAssertEqual(event.metadata["operation"], "privacy_export")
        XCTAssertEqual(event.metadata["error_type"], "export_failure")
        XCTAssertEqual(event.metadata["underlying_error"], "temporary export directory is unavailable")
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

    func testCompletedSessionStillSavesWhenAutoSavePreferenceIsDisabled() async throws {
        let harness = AppStateHarness(autoSaveTranscript: false)
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "forced-auto-save")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "Forced save transcript.", segments: []))
        )

        await harness.appState.startSession()
        await harness.appState.stopSession()

        XCTAssertEqual(harness.transcriptStore.sessions.count, 1)
        XCTAssertEqual(harness.transcriptStore.sessions.first?.transcript, "Forced save transcript.")
        XCTAssertEqual(harness.appState.status.detail, "Session saved. Transcript copied to the clipboard.")
    }

    func testTransientTranscriptionFailurePreservesRetryableSession() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "failure")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        await harness.transcriptionClient.enqueue(.failure(AppError.networkTimeout))

        await harness.appState.startSession()
        await harness.appState.stopSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        let session = try XCTUnwrap(harness.transcriptStore.sessions.first)
        XCTAssertEqual(session.pendingTranscription?.failureReason, .networkTimeout)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(session.pendingTranscriptionAudioURL).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))
        XCTAssertNil(harness.appState.activeRecordingSession)
    }

    func testTranscriptionFailureTelemetryIncludesOperationAndUnderlyingError() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "transcription-underlying-error")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        await harness.transcriptionClient.enqueue(
            .failure(makeFixtureError("provider stream closed before returning text"))
        )

        await harness.appState.startSession()
        await harness.appState.stopSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(
            harness.appState.status.detail,
            AppError.transcriptionFailure("provider stream closed before returning text").userMessage
        )

        let event = try lastAppErrorTelemetry(in: harness)
        XCTAssertEqual(event.metadata["operation"], "transcription")
        XCTAssertEqual(event.metadata["error_type"], "transcription_failure")
        XCTAssertEqual(event.metadata["underlying_error"], "provider stream closed before returning text")
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

        let storageURL = harness.rootDirectoryURL.appendingPathComponent("sessions.index.json")
        try? FileManager.default.removeItem(at: storageURL)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

        await harness.appState.stopSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertTrue(
            harness.appState.status.detail?.hasPrefix("Transcript ready, but Could not save local session history. The transcript is still in memory") == true
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

    func testStopSessionWithoutAPIKeyAfterRecordingPreservesRetryableSession() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "missing-key-on-stop")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]

        await harness.appState.startSession()
        harness.settingsStore.removeAPIKey()
        await harness.appState.stopSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(
            harness.appState.status.detail,
            "Recording saved locally. Add your OpenAI API key in Settings, then retry transcription from this session."
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))
        XCTAssertEqual(harness.transcriptStore.sessions.count, 1)

        let session = try XCTUnwrap(harness.transcriptStore.sessions.first)
        XCTAssertTrue(session.requiresTranscriptionRetry)
        XCTAssertEqual(session.pendingTranscription?.failureReason, .missingAPIKey)
        XCTAssertEqual(session.screenshotCount, 0)
        XCTAssertEqual(session.markerCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(session.pendingTranscriptionAudioURL).path))
    }

    func testStopSessionWithParakeetSetupIssuePreservesRetryableSessionWithProviderMessage() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "parakeet-setup-on-stop")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        harness.settingsStore.aiProvider = .parakeetLocal
        harness.settingsStore.autoExtractIssues = false

        await harness.appState.startSession()
        harness.settingsStore.autoExtractIssues = true
        await harness.appState.stopSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(
            harness.appState.status.detail,
            "Recording saved locally. Finish the Local (Parakeet) setup in Settings, then retry transcription from this session."
        )
        XCTAssertTrue(harness.appState.needsAPIKeySetup)
        XCTAssertEqual(harness.transcriptStore.sessions.first?.pendingTranscription?.failureReason, .providerSetup)
    }

    func testStopSessionWithParakeetUsesLocalProviderRequest() async throws {
        let harness = AppStateHarness(apiKey: "fixture-openai-key")
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "parakeet-stop-session")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        harness.settingsStore.openAIBaseURL = "https://api.openai.com"
        harness.settingsStore.aiProvider = .parakeetLocal
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "Local transcript", segments: []))
        )

        await harness.appState.startSession()
        await harness.appState.stopSession()

        let requestedAPIKeys = await harness.transcriptionClient.requestedAPIKeys
        let requestedModels = await harness.transcriptionClient.requestedModels
        let requestedBaseURLs = await harness.transcriptionClient.requestedBaseURLs
        XCTAssertEqual(requestedAPIKeys, [""])
        XCTAssertEqual(requestedModels, ["parakeet-tdt-0.6b-v3"])
        XCTAssertEqual(requestedBaseURLs.map(\.absoluteString), ["http://localhost:8422"])
        XCTAssertEqual(harness.transcriptStore.sessions.first?.transcript, "Local transcript")
    }

    func testStopSessionWithRejectedAPIKeyPreservesRetryableSession() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "invalid-key-on-stop")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        await harness.transcriptionClient.enqueue(.failure(AppError.invalidAPIKey))

        await harness.appState.startSession()
        await harness.appState.stopSession()

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertEqual(
            harness.appState.status.detail,
            "Recording saved locally. Replace the rejected OpenAI API key in Settings, then retry transcription from this session."
        )

        let session = try XCTUnwrap(harness.transcriptStore.sessions.first)
        XCTAssertEqual(session.pendingTranscription?.failureReason, .invalidAPIKey)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(session.pendingTranscriptionAudioURL).path))
    }

    func testRetryPendingTranscriptionCompletesPreservedSession() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "retry-pending-session")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]

        await harness.appState.startSession()
        harness.settingsStore.removeAPIKey()
        await harness.appState.stopSession()

        let preservedSession = try XCTUnwrap(harness.transcriptStore.sessions.first)
        XCTAssertTrue(preservedSession.requiresTranscriptionRetry)

        harness.settingsStore.apiKey = "restored-key"
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "Recovered transcript", segments: []))
        )

        await harness.appState.retryPendingTranscription(for: preservedSession.id)

        let completedSession = try XCTUnwrap(harness.transcriptStore.session(with: preservedSession.id))
        XCTAssertFalse(completedSession.requiresTranscriptionRetry)
        XCTAssertEqual(completedSession.transcript, "Recovered transcript")
        XCTAssertEqual(harness.appState.status.phase, .success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(preservedSession.pendingTranscriptionAudioURL).path))
    }

    func testRetryPendingTranscriptionHonorsAutoIssueExtraction() async throws {
        let harness = AppStateHarness(autoExtractIssues: true)
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "retry-pending-session-auto-extract")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]

        await harness.appState.startSession()
        harness.settingsStore.removeAPIKey()
        await harness.appState.stopSession()

        let preservedSession = try XCTUnwrap(harness.transcriptStore.sessions.first)
        harness.settingsStore.apiKey = "restored-key"
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "Recovered transcript", segments: []))
        )
        await harness.issueExtractionService.setResult(
            IssueExtractionResult(summary: "Recovered summary", issues: [])
        )

        await harness.appState.retryPendingTranscription(for: preservedSession.id)

        let completedSession = try XCTUnwrap(harness.transcriptStore.session(with: preservedSession.id))
        XCTAssertEqual(completedSession.issueExtraction?.summary, "Recovered summary")
        XCTAssertEqual(harness.appState.status.detail, "Session saved. Transcript and extracted issues are ready.")
    }

    func testCredentialTokenFieldMasksAtRestAndDisablesPasswordAutofillTraits() {
        let field = CredentialTokenTextField()

        field.configureCredentialInput()

        XCTAssertFalse(field.cell is NSSecureTextFieldCell)
        XCTAssertFalse(field.isAutomaticTextCompletionEnabled)
        if #available(macOS 11.0, *) {
            XCTAssertNil(field.contentType)
        }
        XCTAssertEqual(CredentialTokenField.maskedDisplayValue(for: "github_pat_fixture_1234"), "••••••••1234")
        XCTAssertEqual(CredentialTokenField.maskedDisplayValue(for: ""), "")
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

    func testCancelSessionCancelsPendingScreenshotSelectionAndClearsBusyState() async {
        let selectionStarted = expectation(description: "screenshot selection started")
        let selectionService = MockScreenshotSelectionService()
        selectionService.suspendUntilCancelled = true
        selectionService.onSelectRegionStart = {
            selectionStarted.fulfill()
        }
        let harness = AppStateHarness(screenshotSelectionService: selectionService)
        defer { harness.cleanup() }

        await harness.appState.startSession()

        async let capture: Void = harness.appState.captureScreenshot()
        await fulfillment(of: [selectionStarted], timeout: 1.0)

        XCTAssertTrue(harness.appState.isScreenshotCaptureInProgress)

        await harness.appState.cancelSession()
        _ = await capture

        XCTAssertEqual(selectionService.cancelActiveSelectionCallCount, 1)
        XCTAssertFalse(harness.appState.isScreenshotCaptureInProgress)
        XCTAssertEqual(harness.appState.status.phase, .idle)
        XCTAssertNil(harness.appState.activeRecordingSession)
    }

    func testStopSessionCancelsPendingScreenshotSelectionAndClearsBusyState() async throws {
        let selectionStarted = expectation(description: "screenshot selection started")
        let selectionService = MockScreenshotSelectionService()
        selectionService.suspendUntilCancelled = true
        selectionService.onSelectRegionStart = {
            selectionStarted.fulfill()
        }
        let harness = AppStateHarness(screenshotSelectionService: selectionService)
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "stopped-with-pending-screenshot")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "Stopped while screenshot selection was open.", segments: []))
        )

        await harness.appState.startSession()

        async let capture: Void = harness.appState.captureScreenshot()
        await fulfillment(of: [selectionStarted], timeout: 1.0)

        XCTAssertTrue(harness.appState.isScreenshotCaptureInProgress)

        await harness.appState.stopSession()
        _ = await capture

        XCTAssertEqual(selectionService.cancelActiveSelectionCallCount, 1)
        XCTAssertFalse(harness.appState.isScreenshotCaptureInProgress)
        XCTAssertEqual(harness.appState.status.phase, .success)
        XCTAssertNil(harness.appState.activeRecordingSession)
    }

    func testCaptureScreenshotFailureKeepsRecordingAndShowsMessage() async throws {
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

        let event = try lastAppErrorTelemetry(in: harness)
        XCTAssertEqual(event.metadata["operation"], "screenshot_capture")
        XCTAssertEqual(event.metadata["error_type"], "screenshot_capture_failure")
        XCTAssertNil(event.metadata["underlying_error"])
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

        let storageURL = harness.rootDirectoryURL.appendingPathComponent("sessions.index.json")
        try FileManager.default.removeItem(at: storageURL)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

        var updatedIssue = originalIssue
        updatedIssue.title = "Updated visible title"

        harness.appState.updateExtractedIssue(updatedIssue, in: session.id)

        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertTrue(
            harness.appState.status.detail?.hasPrefix("Could not save local session history. The transcript is still in memory") == true
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

    // MARK: - Concurrent Retry Guard

    func testRetryPendingTranscriptionClearsRetryingSessionIDOnSuccess() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "retry-guard-success")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]

        await harness.appState.startSession()
        harness.settingsStore.removeAPIKey()
        await harness.appState.stopSession()

        let preservedSession = try XCTUnwrap(harness.transcriptStore.sessions.first)

        harness.settingsStore.apiKey = "restored-key"
        await harness.transcriptionClient.enqueue(
            .success(TranscriptionResult(text: "Recovered", segments: []))
        )

        XCTAssertNil(harness.appState.retryingSessionID)
        await harness.appState.retryPendingTranscription(for: preservedSession.id)
        XCTAssertNil(harness.appState.retryingSessionID)
    }

    func testRetryPendingTranscriptionClearsRetryingSessionIDOnFailure() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "retry-guard-failure")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]

        await harness.appState.startSession()
        harness.settingsStore.removeAPIKey()
        await harness.appState.stopSession()

        let preservedSession = try XCTUnwrap(harness.transcriptStore.sessions.first)

        harness.settingsStore.apiKey = "restored-key"
        await harness.transcriptionClient.enqueue(
            .failure(AppError.invalidAPIKey)
        )

        await harness.appState.retryPendingTranscription(for: preservedSession.id)
        XCTAssertNil(harness.appState.retryingSessionID)
    }

    // MARK: - Attempt Counting

    func testRetryPendingTranscriptionIncrementsAttemptCount() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "retry-attempt-count")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]

        await harness.appState.startSession()
        harness.settingsStore.removeAPIKey()
        await harness.appState.stopSession()

        let preservedSession = try XCTUnwrap(harness.transcriptStore.sessions.first)
        XCTAssertEqual(preservedSession.pendingTranscription?.attemptCount, 0)

        harness.settingsStore.apiKey = "restored-key"
        await harness.transcriptionClient.enqueue(
            .failure(AppError.invalidAPIKey)
        )

        await harness.appState.retryPendingTranscription(for: preservedSession.id)

        let updatedSession = try XCTUnwrap(harness.transcriptStore.session(with: preservedSession.id))
        XCTAssertEqual(updatedSession.pendingTranscription?.attemptCount, 1)
    }

    func testPendingTranscriptionAttemptCountDefaultsToZeroForLegacyData() throws {
        let json = """
        {
            "audioFileName": "test.m4a",
            "failureReason": "missingAPIKey",
            "preservedAt": 0
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(PendingTranscription.self, from: data)
        XCTAssertEqual(decoded.attemptCount, 0)
    }

    private func makeFixtureError(_ message: String) -> NSError {
        NSError(
            domain: "BugNarratorTests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func lastAppErrorTelemetry(
        in harness: AppStateHarness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (name: String, metadata: [String: String]) {
        try XCTUnwrap(
            harness.telemetryRecorder.recordedEvents.last { $0.name == TelemetryEvent.appError.rawValue },
            file: file,
            line: line
        )
    }
}
