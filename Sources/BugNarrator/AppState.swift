import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var status: AppStatus = .idle()
    @Published private(set) var elapsedDuration: TimeInterval = 0
    @Published var showDiscardConfirmation = false
    @Published var currentTranscript: TranscriptSession?
    @Published var selectedTranscriptID: UUID?
    @Published private(set) var activeRecordingSession: RecordingSessionDraft?
    @Published private(set) var issueExtractionSessionID: UUID?
    @Published private(set) var exportDestinationInProgress: ExportDestination?
    @Published private(set) var apiKeyValidationState: APIKeyValidationState = .idle

    let settingsStore: SettingsStore
    let transcriptStore: TranscriptStore

    var showTranscriptWindow: (() -> Void)?
    var showSettingsWindow: (() -> Void)?
    var showAboutWindow: (() -> Void)?
    var showChangelogWindow: (() -> Void)?
    var showSupportWindow: (() -> Void)?

    private let audioRecorder: any AudioRecording
    private let transcriptionClient: any TranscriptionServing
    private let hotkeyManager: any HotkeyManaging
    private let screenshotCaptureService: any ScreenshotCapturing
    private let issueExtractionService: any IssueExtracting
    private let exportService: any IssueExporting
    private let artifactsService: any SessionArtifactsManaging
    private let clipboardService: any ClipboardWriting
    private let urlHandler: any URLOpening

    private var timerTask: Task<Void, Never>?
    private var processActivity: NSObjectProtocol?
    private var pendingRecordedAudio: RecordedAudio?
    private var cancellables = Set<AnyCancellable>()
    private var isStartingSession = false
    private var isStoppingSession = false
    private var isCancellingSession = false
    private var isValidatingAPIKey = false
    private var isCapturingScreenshot = false

    init(
        settingsStore: SettingsStore,
        transcriptStore: TranscriptStore,
        audioRecorder: AudioRecording = AudioRecorder(),
        transcriptionClient: any TranscriptionServing = TranscriptionClient(),
        hotkeyManager: any HotkeyManaging = HotkeyManager(),
        screenshotCaptureService: any ScreenshotCapturing = ScreenshotCaptureService(),
        issueExtractionService: any IssueExtracting = IssueExtractionService(),
        exportService: any IssueExporting = ExportService(),
        artifactsService: any SessionArtifactsManaging = SessionArtifactsService(),
        clipboardService: any ClipboardWriting = SystemClipboardService(),
        urlHandler: any URLOpening = WorkspaceURLHandler()
    ) {
        self.settingsStore = settingsStore
        self.transcriptStore = transcriptStore
        self.audioRecorder = audioRecorder
        self.transcriptionClient = transcriptionClient
        self.hotkeyManager = hotkeyManager
        self.screenshotCaptureService = screenshotCaptureService
        self.issueExtractionService = issueExtractionService
        self.exportService = exportService
        self.artifactsService = artifactsService
        self.clipboardService = clipboardService
        self.urlHandler = urlHandler
        self.selectedTranscriptID = transcriptStore.sessions.first?.id

        self.hotkeyManager.onHotKeyPressed = { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleHotKeyPressed(action)
            }
        }

        settingsStore.$recordingHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .toggleRecording)
            }
            .store(in: &cancellables)

        settingsStore.$markerHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .insertMarker)
            }
            .store(in: &cancellables)

        settingsStore.$screenshotHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .captureScreenshot)
            }
            .store(in: &cancellables)

        settingsStore.$apiKey
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.apiKeyValidationState = .idle
            }
            .store(in: &cancellables)

        hotkeyManager.register(shortcut: settingsStore.recordingHotkeyShortcut, for: .toggleRecording)
        hotkeyManager.register(shortcut: settingsStore.markerHotkeyShortcut, for: .insertMarker)
        hotkeyManager.register(shortcut: settingsStore.screenshotHotkeyShortcut, for: .captureScreenshot)
    }

    var elapsedTimeString: String {
        ElapsedTimeFormatter.string(from: elapsedDuration)
    }

    var activeMarkerCount: Int {
        activeRecordingSession?.markers.count ?? 0
    }

    var activeScreenshotCount: Int {
        activeRecordingSession?.screenshots.count ?? 0
    }

    var displayedTranscript: TranscriptSession? {
        if let selectedTranscriptID {
            if let storedSession = transcriptStore.session(with: selectedTranscriptID) {
                return storedSession
            }

            if currentTranscript?.id == selectedTranscriptID {
                return currentTranscript
            }
        }

        if let currentTranscript {
            return currentTranscript
        }

        return transcriptStore.sessions.first
    }

    var currentTranscriptIsPersisted: Bool {
        guard let currentTranscript else {
            return false
        }

        return transcriptStore.session(with: currentTranscript.id) != nil
    }

    var needsAPIKeySetup: Bool {
        !settingsStore.hasAPIKey
    }

    func isExtractingIssues(for session: TranscriptSession) -> Bool {
        issueExtractionSessionID == session.id
    }

    func isExporting(to destination: ExportDestination) -> Bool {
        exportDestinationInProgress == destination
    }

    func canExportIssues(from session: TranscriptSession, to destination: ExportDestination) -> Bool {
        guard status.phase != .recording,
              status.phase != .transcribing,
              let extraction = session.issueExtraction,
              !extraction.selectedIssues.isEmpty else {
            return false
        }

        switch destination {
        case .github:
            return settingsStore.githubExportConfiguration != nil
        case .jira:
            return settingsStore.jiraExportConfiguration != nil
        }
    }

    func startSession() async {
        guard !isStartingSession, !isStoppingSession, !isCancellingSession else {
            return
        }

        guard status.phase != .recording, status.phase != .transcribing else {
            return
        }

        if let preflightError = await preflightForSessionStart() {
            presentError(preflightError)
            return
        }

        isStartingSession = true
        defer { isStartingSession = false }

        do {
            if let activeRecordingSession {
                artifactsService.removeArtifactsDirectory(at: activeRecordingSession.artifactsDirectoryURL)
                self.activeRecordingSession = nil
            }

            let sessionID = UUID()
            let artifactsDirectoryURL = try artifactsService.createArtifactsDirectory(for: sessionID)

            do {
                try await audioRecorder.startRecording()
                pendingRecordedAudio = nil
                elapsedDuration = 0
                activeRecordingSession = RecordingSessionDraft(
                    sessionID: sessionID,
                    artifactsDirectoryURL: artifactsDirectoryURL
                )
                status = .recording("Recording in progress.")
                beginActivity(reason: "Recording a spoken feedback session")
                startTimer()
            } catch {
                artifactsService.removeArtifactsDirectory(at: artifactsDirectoryURL)
                throw error
            }
        } catch {
            presentError(error)
        }
    }

    func stopSession() async {
        guard !isStoppingSession, !isCancellingSession else {
            return
        }

        guard status.phase == .recording else {
            return
        }

        guard let recordingSession = activeRecordingSession else {
            presentError(AppError.recordingFailure("The recording session metadata was unavailable."))
            return
        }

        isStoppingSession = true
        defer { isStoppingSession = false }

        stopTimer(resetElapsed: false)

        do {
            let recordedAudio = try await audioRecorder.stopRecording()
            pendingRecordedAudio = recordedAudio

            guard settingsStore.hasAPIKey else {
                throw AppError.missingAPIKey
            }

            status = .transcribing("Uploading audio to OpenAI and waiting for transcription...")
            swapActivity(reason: "Uploading audio for transcription")

            let request = TranscriptionRequest(
                model: settingsStore.preferredModelValue,
                languageHint: settingsStore.normalizedLanguageHint,
                prompt: settingsStore.normalizedPrompt
            )

            let transcriptionResult = try await transcriptionClient.transcribe(
                fileURL: recordedAudio.fileURL,
                apiKey: settingsStore.trimmedAPIKey,
                request: request
            )

            let sections = TranscriptSectionBuilder.buildSections(
                transcript: transcriptionResult.text,
                segments: transcriptionResult.segments,
                markers: recordingSession.markers,
                duration: recordedAudio.duration
            )

            var session = TranscriptSession(
                id: recordingSession.sessionID,
                createdAt: Date(),
                transcript: transcriptionResult.text,
                duration: recordedAudio.duration,
                model: request.model,
                languageHint: request.languageHint,
                prompt: request.prompt,
                markers: recordingSession.markers,
                screenshots: recordingSession.screenshots,
                sections: sections,
                artifactsDirectoryPath: recordingSession.artifactsDirectoryURL.path
            )

            currentTranscript = session
            activeRecordingSession = nil
            try persistCompletedTranscript(session)
            showTranscriptWindow?()

            if settingsStore.autoExtractIssues {
                issueExtractionSessionID = session.id
                status = .transcribing("Extracting reviewable issues...")
                swapActivity(reason: "Extracting review issues")

                do {
                    let extraction = try await issueExtractionService.extractIssues(
                        from: session,
                        apiKey: settingsStore.trimmedAPIKey,
                        model: settingsStore.issueExtractionModelValue
                    )
                    session.issueExtraction = extraction
                    try persistUpdatedSession(session)
                } catch {
                    cleanupPendingRecordedAudioIfNeeded()
                    endActivity()
                    issueExtractionSessionID = nil
                    presentPostTranscriptionError(error)
                    return
                }

                issueExtractionSessionID = nil
            }

            cleanupPendingRecordedAudioIfNeeded()
            endActivity()
            status = .success(
                settingsStore.autoExtractIssues
                    ? "Transcript and extracted issues are ready."
                    : (settingsStore.autoCopyTranscript
                        ? "Transcript copied to the clipboard."
                        : "Transcript ready.")
            )
        } catch {
            if !settingsStore.debugMode {
                artifactsService.removeArtifactsDirectory(at: recordingSession.artifactsDirectoryURL)
            }
            activeRecordingSession = nil
            presentError(error)
        }
    }

    func requestSessionCancel() {
        guard status.phase == .recording else {
            return
        }

        showDiscardConfirmation = true
    }

    func cancelSession() async {
        guard !isCancellingSession, !isStoppingSession else {
            return
        }

        isCancellingSession = true
        defer { isCancellingSession = false }

        showDiscardConfirmation = false
        stopTimer(resetElapsed: true)
        endActivity()
        await audioRecorder.cancelRecording(preserveFile: settingsStore.debugMode)
        if let activeRecordingSession {
            artifactsService.removeArtifactsDirectory(at: activeRecordingSession.artifactsDirectoryURL)
            self.activeRecordingSession = nil
        }
        pendingRecordedAudio = nil
        status = .idle("Session discarded.")
    }

    func openTranscriptHistory() {
        showTranscriptWindow?()
    }

    func openSettings() {
        settingsStore.refreshSecretsForUserInitiatedAccess()
        showSettingsWindow?()
    }

    func openAbout() {
        showAboutWindow?()
    }

    func openChangelog() {
        showChangelogWindow?()
    }

    func openGitHubRepository() {
        openExternalURL(BugNarratorLinks.repository, label: "GitHub repository")
    }

    func openDocumentation() {
        openExternalURL(BugNarratorLinks.documentation, label: "documentation")
    }

    func openIssueReporter() {
        openExternalURL(BugNarratorLinks.issues, label: "issue tracker")
    }

    func openSupportDevelopment() {
        showSupportWindow?()
    }

    func openSupportDonationPage() {
        openExternalURL(BugNarratorLinks.supportDevelopment, label: "PayPal donation page")
    }

    func checkForUpdates() {
        openExternalURL(BugNarratorLinks.releases, label: "releases page")
    }

    func validateAPIKey() async {
        guard !isValidatingAPIKey else {
            return
        }

        settingsStore.refreshOpenAISecretForUserInitiatedAccess()

        guard settingsStore.hasAPIKey else {
            apiKeyValidationState = .failure(AppError.missingAPIKey.userMessage)
            showSettingsWindow?()
            return
        }

        isValidatingAPIKey = true
        apiKeyValidationState = .validating
        defer { isValidatingAPIKey = false }

        do {
            try await transcriptionClient.validateAPIKey(settingsStore.trimmedAPIKey)
            apiKeyValidationState = .success("OpenAI accepted this key.")
        } catch {
            let appError = (error as? AppError) ?? .transcriptionFailure(error.localizedDescription)
            apiKeyValidationState = .failure(appError.userMessage)
        }
    }

    func removeAPIKey() {
        settingsStore.removeAPIKey()
        apiKeyValidationState = .idle
    }

    func copyDisplayedTranscript() {
        guard let transcript = displayedTranscript else {
            return
        }

        clipboardService.copy(transcript.transcript)
        status = .success("Transcript copied to the clipboard.")
    }

    func saveCurrentTranscriptToHistory() {
        guard let currentTranscript, !currentTranscriptIsPersisted else {
            selectedTranscriptID = currentTranscript?.id
            return
        }

        do {
            try transcriptStore.add(currentTranscript)
            selectedTranscriptID = currentTranscript.id
            status = .success("Transcript saved to session history.")
        } catch {
            presentError(error)
        }
    }

    func deleteDisplayedTranscript() {
        guard let displayedTranscript else {
            return
        }

        deleteSessions(withIDs: [displayedTranscript.id])
    }

    func deleteSessions(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }

        let wasSelectedTranscriptDeleted = selectedTranscriptID.map(ids.contains) ?? false
        let deletingUnsavedCurrentTranscript = currentTranscript
            .map { ids.contains($0.id) && transcriptStore.session(with: $0.id) == nil }
            ?? false

        do {
            let removedSessions = try transcriptStore.removeSessions(withIDs: ids)
            var sessionsToCleanup = removedSessions
            if let currentTranscript,
               ids.contains(currentTranscript.id),
               !removedSessions.contains(where: { $0.id == currentTranscript.id }),
               transcriptStore.session(with: currentTranscript.id) == nil {
                sessionsToCleanup.append(currentTranscript)
            }
            sessionsToCleanup.forEach(cleanupArtifactsForDeletedSession)

            if currentTranscript.map({ ids.contains($0.id) }) == true {
                currentTranscript = nil
            }

            if wasSelectedTranscriptDeleted || selectedTranscriptID == nil {
                selectedTranscriptID = preferredTranscriptSelection()
            }

            let deletedCount = removedSessions.count + (deletingUnsavedCurrentTranscript ? 1 : 0)
            if deletedCount > 0 {
                status = .success(deletedCount == 1 ? "Deleted 1 session." : "Deleted \(deletedCount) sessions.")
            }
        } catch {
            presentError(error)
        }
    }

    func insertMarker(
        title: String? = nil,
        note: String? = nil,
        captureScreenshot: Bool = false
    ) async {
        guard status.phase == .recording, var recordingSession = activeRecordingSession else {
            status = .error(AppError.noActiveSession("Start a feedback session before inserting a marker.").userMessage)
            return
        }

        let markerIndex = recordingSession.markers.count + 1
        let elapsedTime = max(audioRecorder.currentDuration, elapsedDuration)
        let markerTitle = normalizedMarkerTitle(title, index: markerIndex)
        let markerID = UUID()

        var screenshot: SessionScreenshot?
        var statusMessage = "Inserted \(markerTitle)."

        if captureScreenshot {
            do {
                screenshot = try performScreenshotCapture(
                    into: &recordingSession,
                    prefix: "marker",
                    index: recordingSession.screenshots.count + 1,
                    elapsedTime: elapsedTime,
                    associatedMarkerID: markerID
                )
                statusMessage = "Inserted \(markerTitle) with a screenshot."
            } catch {
                statusMessage = "\(markerTitle) was inserted, but the screenshot failed."
            }
        }

        recordingSession.markers.append(
            SessionMarker(
                id: markerID,
                index: markerIndex,
                elapsedTime: elapsedTime,
                title: markerTitle,
                note: normalizeOptional(note),
                screenshotID: screenshot?.id
            )
        )

        activeRecordingSession = recordingSession
        status = .recording(statusMessage)
    }

    func captureScreenshot() async {
        guard status.phase == .recording, var recordingSession = activeRecordingSession else {
            status = .error(AppError.noActiveSession("Start a feedback session before capturing a screenshot.").userMessage)
            return
        }

        guard !isCapturingScreenshot else {
            return
        }

        isCapturingScreenshot = true
        defer { isCapturingScreenshot = false }

        let screenshotIndex = recordingSession.screenshots.count + 1
        let elapsedTime = max(audioRecorder.currentDuration, elapsedDuration)
        let associatedMarkerID = nearestMarkerID(in: recordingSession, to: elapsedTime)

        do {
            _ = try performScreenshotCapture(
                into: &recordingSession,
                prefix: "capture",
                index: screenshotIndex,
                elapsedTime: elapsedTime,
                associatedMarkerID: associatedMarkerID
            )
            activeRecordingSession = recordingSession
            status = .recording("Captured Screenshot \(screenshotIndex).")
        } catch {
            activeRecordingSession = recordingSession
            let appError = (error as? AppError) ?? .screenshotCaptureFailure(error.localizedDescription)
            status = .recording(appError.userMessage)
        }
    }

    func extractIssuesForDisplayedTranscript() async {
        guard let transcriptSession = displayedTranscript else {
            return
        }

        settingsStore.refreshOpenAISecretForUserInitiatedAccess()

        guard let preflightError = preflightForIssueExtraction(transcriptSession) else {
            issueExtractionSessionID = transcriptSession.id
            status = .transcribing("Extracting reviewable issues...")
            beginActivity(reason: "Extracting review issues")

            do {
                let extraction = try await issueExtractionService.extractIssues(
                    from: transcriptSession,
                    apiKey: settingsStore.trimmedAPIKey,
                    model: settingsStore.issueExtractionModelValue
                )

                var updatedSession = transcriptSession
                updatedSession.issueExtraction = extraction
                try persistUpdatedSession(updatedSession)

                issueExtractionSessionID = nil
                endActivity()
                status = .success("Extracted \(extraction.issues.count) review issues.")
                showTranscriptWindow?()
            } catch {
                issueExtractionSessionID = nil
                presentError(error)
            }

            return
        }

        presentError(preflightError)
    }

    func updateExtractedIssue(_ updatedIssue: ExtractedIssue, in sessionID: UUID) {
        guard var session = editableSession(with: sessionID),
              var extraction = session.issueExtraction,
              let issueIndex = extraction.issues.firstIndex(where: { $0.id == updatedIssue.id }) else {
            return
        }

        extraction.issues[issueIndex] = updatedIssue
        session.issueExtraction = extraction

        do {
            try persistUpdatedSession(session)
        } catch {
            presentError(error)
        }
    }

    func setIssueSelection(_ isSelected: Bool, issueID: UUID, in sessionID: UUID) {
        guard var session = editableSession(with: sessionID),
              var extraction = session.issueExtraction,
              let issueIndex = extraction.issues.firstIndex(where: { $0.id == issueID }) else {
            return
        }

        extraction.issues[issueIndex].isSelectedForExport = isSelected
        session.issueExtraction = extraction

        do {
            try persistUpdatedSession(session)
        } catch {
            presentError(error)
        }
    }

    func setAllIssuesSelected(_ isSelected: Bool, in sessionID: UUID) {
        guard var session = editableSession(with: sessionID),
              var extraction = session.issueExtraction else {
            return
        }

        extraction.issues = extraction.issues.map { issue in
            var updatedIssue = issue
            updatedIssue.isSelectedForExport = isSelected
            return updatedIssue
        }
        session.issueExtraction = extraction

        do {
            try persistUpdatedSession(session)
        } catch {
            presentError(error)
        }
    }

    func exportSelectedIssues(from session: TranscriptSession, to destination: ExportDestination) async {
        guard let extraction = session.issueExtraction else {
            presentError(AppError.exportFailure("Run issue extraction before exporting."))
            return
        }

        let selectedIssues = extraction.selectedIssues
        guard !selectedIssues.isEmpty else {
            presentError(AppError.exportFailure("Select at least one extracted issue to export."))
            return
        }

        settingsStore.refreshExportSecretsForUserInitiatedAccess()

        do {
            try validateExportConfiguration(for: destination)
        } catch {
            presentError(error)
            if case .exportConfigurationMissing = error as? AppError {
                showSettingsWindow?()
            }
            return
        }

        exportDestinationInProgress = destination
        status = .transcribing("Exporting \(selectedIssues.count) issues to \(destination.rawValue)...")
        beginActivity(reason: "Exporting extracted issues")

        do {
            let results: [ExportResult]

            switch destination {
            case .github:
                guard let configuration = settingsStore.githubExportConfiguration else {
                    throw AppError.exportConfigurationMissing(
                        "GitHub export requires a token, repository owner, and repository name."
                    )
                }
                results = try await exportService.exportToGitHub(
                    issues: selectedIssues,
                    session: session,
                    configuration: configuration
                )
            case .jira:
                guard let configuration = settingsStore.jiraExportConfiguration else {
                    throw AppError.exportConfigurationMissing(
                        "Jira export requires a base URL, email, API token, project key, and issue type."
                    )
                }
                results = try await exportService.exportToJira(
                    issues: selectedIssues,
                    session: session,
                    configuration: configuration
                )
            }

            exportDestinationInProgress = nil
            endActivity()
            status = .success("Exported \(results.count) issues to \(destination.rawValue).")
        } catch {
            exportDestinationInProgress = nil
            presentError(error)
        }
    }

    func openScreenshot(_ screenshot: SessionScreenshot) {
        guard FileManager.default.fileExists(atPath: screenshot.fileURL.path) else {
            presentUtilityActionFailure("The selected screenshot file is no longer available on this Mac.")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([screenshot.fileURL])
    }

    private func handleHotKeyPressed(_ action: HotkeyAction) {
        switch action {
        case .toggleRecording:
            switch status.phase {
            case .idle, .success, .error:
                Task {
                    await startSession()
                }
            case .recording:
                Task {
                    await stopSession()
                }
            case .transcribing:
                break
            }
        case .insertMarker:
            Task {
                await insertMarker()
            }
        case .captureScreenshot:
            Task {
                await captureScreenshot()
            }
        }
    }

    private func openExternalURL(_ url: URL, label: String) {
        guard urlHandler.open(url) else {
            presentUtilityActionFailure("BugNarrator could not open the \(label).")
            return
        }
    }

    private func presentUtilityActionFailure(_ message: String) {
        switch status.phase {
        case .recording:
            status = .recording("\(message) Recording is still active.")
        case .transcribing:
            status = .transcribing("\(message) Background work is still in progress.")
        case .idle, .success, .error:
            status = .error(message)
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        let startDate = Date()

        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.elapsedDuration = Date().timeIntervalSince(startDate)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopTimer(resetElapsed: Bool) {
        timerTask?.cancel()
        timerTask = nil

        if resetElapsed {
            elapsedDuration = 0
        }
    }

    private func beginActivity(reason: String) {
        endActivity()
        processActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
    }

    private func swapActivity(reason: String) {
        beginActivity(reason: reason)
    }

    private func endActivity() {
        if let processActivity {
            ProcessInfo.processInfo.endActivity(processActivity)
        }

        processActivity = nil
    }

    private func presentError(_ error: Error) {
        stopTimer(resetElapsed: status.phase == .recording)
        endActivity()
        cleanupPendingRecordedAudioIfNeeded()
        issueExtractionSessionID = nil
        exportDestinationInProgress = nil

        let appError = (error as? AppError) ?? .transcriptionFailure(error.localizedDescription)
        status = .error(appError.userMessage)

        switch appError {
        case .missingAPIKey, .invalidAPIKey, .revokedAPIKey, .exportConfigurationMissing:
            showSettingsWindow?()
        default:
            break
        }
    }

    private func presentPostTranscriptionError(_ error: Error) {
        let appError = (error as? AppError) ?? .issueExtractionFailure(error.localizedDescription)
        status = .error("Transcript ready, but \(appError.userMessage)")

        switch appError {
        case .missingAPIKey, .invalidAPIKey, .revokedAPIKey:
            showSettingsWindow?()
        default:
            break
        }
    }

    private func cleanupPendingRecordedAudioIfNeeded() {
        guard let pendingRecordedAudio else {
            return
        }

        if !settingsStore.debugMode {
            try? FileManager.default.removeItem(at: pendingRecordedAudio.fileURL)
        }

        self.pendingRecordedAudio = nil
    }

    private func persistCompletedTranscript(_ session: TranscriptSession) throws {
        if settingsStore.autoSaveTranscript {
            try transcriptStore.add(session)
            selectedTranscriptID = session.id
        } else {
            selectedTranscriptID = session.id
        }

        if settingsStore.autoCopyTranscript {
            clipboardService.copy(session.transcript)
        }
    }

    private func persistUpdatedSession(_ session: TranscriptSession) throws {
        var session = session
        session.updatedAt = Date()

        if currentTranscript?.id == session.id {
            currentTranscript = session
        }

        if transcriptStore.session(with: session.id) != nil {
            try transcriptStore.add(session)
        }

        selectedTranscriptID = session.id
    }

    private func preflightForSessionStart() async -> AppError? {
        settingsStore.refreshOpenAISecretForUserInitiatedAccess()

        guard settingsStore.hasAPIKey else {
            return .missingAPIKey
        }

        switch audioRecorder.microphonePermissionState() {
        case .denied, .restricted:
            return .microphonePermissionDenied
        case .authorized, .notDetermined:
            return nil
        }
    }

    private func preflightForIssueExtraction(_ session: TranscriptSession) -> AppError? {
        guard settingsStore.hasAPIKey else {
            return .missingAPIKey
        }

        let transcript = session.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            return .emptyTranscript
        }

        guard status.phase != .recording else {
            return .recordingFailure("Stop the current recording before extracting issues.")
        }

        return nil
    }

    private func validateExportConfiguration(for destination: ExportDestination) throws {
        switch destination {
        case .github:
            guard settingsStore.githubExportConfiguration != nil else {
                throw AppError.exportConfigurationMissing(
                    "GitHub export requires a token, repository owner, and repository name."
                )
            }
        case .jira:
            guard settingsStore.jiraExportConfiguration != nil else {
                throw AppError.exportConfigurationMissing(
                    "Jira export requires a base URL, email, API token, project key, and issue type."
                )
            }
        }
    }

    private func editableSession(with sessionID: UUID) -> TranscriptSession? {
        if currentTranscript?.id == sessionID {
            return currentTranscript
        }

        return transcriptStore.session(with: sessionID)
    }

    private func preferredTranscriptSelection() -> UUID? {
        if let currentTranscript, transcriptStore.session(with: currentTranscript.id) == nil {
            return currentTranscript.id
        }

        return transcriptStore.sessions.first?.id
    }

    private func cleanupArtifactsForDeletedSession(_ session: TranscriptSession) {
        if let artifactsDirectoryURL = session.artifactsDirectoryURL {
            artifactsService.removeArtifactsDirectory(at: artifactsDirectoryURL)
            return
        }

        let directories = Set(
            session.screenshots.map { screenshot in
                screenshot.fileURL.deletingLastPathComponent()
            }
        )

        directories.forEach { directoryURL in
            artifactsService.removeArtifactsDirectory(at: directoryURL)
        }
    }

    private func performScreenshotCapture(
        into recordingSession: inout RecordingSessionDraft,
        prefix: String,
        index: Int,
        elapsedTime: TimeInterval,
        associatedMarkerID: UUID?
    ) throws -> SessionScreenshot {
        let screenshotURL = artifactsService.makeScreenshotURL(
            in: recordingSession.artifactsDirectoryURL,
            prefix: prefix,
            index: index,
            elapsedTime: elapsedTime
        )

        try screenshotCaptureService.captureScreenshot(to: screenshotURL)

        let screenshot = SessionScreenshot(
            elapsedTime: elapsedTime,
            filePath: screenshotURL.path,
            associatedMarkerID: associatedMarkerID
        )
        recordingSession.screenshots.append(screenshot)
        return screenshot
    }

    private func normalizedMarkerTitle(_ title: String?, index: Int) -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedTitle.isEmpty ? "Marker \(index)" : trimmedTitle
    }

    private func normalizeOptional(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func nearestMarkerID(
        in recordingSession: RecordingSessionDraft,
        to elapsedTime: TimeInterval,
        threshold: TimeInterval = 5
    ) -> UUID? {
        recordingSession.markers
            .map { marker in
                (markerID: marker.id, distance: abs(marker.elapsedTime - elapsedTime))
            }
            .filter { $0.distance <= threshold }
            .min { $0.distance < $1.distance }?
            .markerID
    }
}
