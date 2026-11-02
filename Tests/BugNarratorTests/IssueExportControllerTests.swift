import XCTest
@testable import BugNarrator

@MainActor
final class IssueExportControllerTests: XCTestCase {
    func testStatusPresenterMapsIssueExportStatuses() {
        let completion = IssueExportCompletion(
            destination: .github,
            sessionID: UUID(),
            results: [],
            duplicateCount: 1,
            performedRemoteExport: false
        )

        XCTAssertEqual(
            IssueExportStatusPresenter.reviewPreparationStatus(destination: .github),
            .transcribing("Checking GitHub for similar open issues...")
        )
        XCTAssertEqual(
            IssueExportStatusPresenter.reviewReadyStatus(destination: .jira),
            .success("Review the similar Jira issues before export.")
        )
        XCTAssertEqual(
            IssueExportStatusPresenter.remoteExportStatus(destination: .github),
            .transcribing("Exporting reviewed issues to GitHub...")
        )
        XCTAssertEqual(
            IssueExportStatusPresenter.completionStatus(completion),
            .success(completion.summary)
        )
    }

    func testIssueExportPresentationControllerSetsExportStatuses() {
        let harness = makeIssueExportPresentationController()
        let completion = IssueExportCompletion(
            destination: .github,
            sessionID: UUID(),
            results: [],
            duplicateCount: 1,
            performedRemoteExport: false
        )

        harness.presenter.presentReviewPreparation(destination: .github)
        XCTAssertEqual(
            harness.presentationState.status,
            IssueExportStatusPresenter.reviewPreparationStatus(destination: .github)
        )

        harness.presenter.presentReviewReady(destination: .jira)
        XCTAssertEqual(
            harness.presentationState.status,
            IssueExportStatusPresenter.reviewReadyStatus(destination: .jira)
        )

        harness.presenter.presentRemoteExportStarted(destination: .github)
        XCTAssertEqual(
            harness.presentationState.status,
            IssueExportStatusPresenter.remoteExportStatus(destination: .github)
        )

        harness.presenter.presentCompletion(completion)
        XCTAssertEqual(harness.presentationState.status, IssueExportStatusPresenter.completionStatus(completion))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertEqual(harness.settingsWindowOpenCount(), 0)
    }

    func testIssueExportPresentationControllerOpensSettingsForConfigurationFailure() {
        let harness = makeIssueExportPresentationController()
        let expectedError = AppError.exportConfigurationMissing("GitHub token is missing.")
        let failure = IssueExportPreflightFailure(error: expectedError, opensSettings: true)

        harness.presenter.presentPreflightFailure(failure)

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.settingsWindowOpenCount(), 1)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata["operation"], "export")
    }

    func testIssueExportPresentationControllerOpensSettingsForMissingAPIKeyFailure() {
        let harness = makeIssueExportPresentationController()
        let expectedError = AppError.missingAPIKey
        let failure = IssueExportPreflightFailure(error: expectedError, opensSettings: false)

        harness.presenter.presentPreflightFailure(failure)

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.settingsWindowOpenCount(), 1)
    }

    func testIssueExportPresentationControllerNormalizesGenericExportFailure() {
        let harness = makeIssueExportPresentationController()
        let error = NSError(
            domain: "BugNarratorTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Remote export failed"]
        )
        let expectedError = AppError.exportFailure("Remote export failed")

        harness.presenter.presentFailure(error)

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.settingsWindowOpenCount(), 0)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata["operation"], "export")
    }

    func testReadinessAndDefaultGitHubRouting() throws {
        let harness = try IssueExportControllerHarness()
        defer { harness.cleanup() }

        let session = harness.makeSession(issues: [harness.makeIssue(title: "Exportable issue")])
        try harness.transcriptStore.add(session)

        XCTAssertTrue(harness.controller.canRequestIssueExport(from: session, statusPhase: .idle))
        XCTAssertFalse(harness.controller.canExportIssues(from: session, to: .github, statusPhase: .idle))
        XCTAssertEqual(
            harness.controller.issueExportSetupMessage(for: .github),
            "GitHub token is missing. Click Set Up GitHub to open Settings."
        )

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        harness.settingsStore.githubRepositoryID = "R_kgDOFixture"
        harness.settingsStore.githubDefaultLabels = "bug, triage"

        XCTAssertTrue(harness.controller.canExportIssues(from: session, to: .github, statusPhase: .idle))
        XCTAssertNil(harness.controller.issueExportSetupMessage(for: .github))
        XCTAssertNil(harness.controller.issueExportRoutingMessage(for: .github, session: session))
        XCTAssertEqual(harness.controller.defaultGitHubIssueExportTarget()?.displayLabel, "acme/bugnarrator")
        XCTAssertEqual(harness.controller.defaultGitHubIssueExportTarget()?.labels, ["bug", "triage"])
    }

    func testGitHubGroupingUsesPerIssueTargets() async throws {
        let harness = try IssueExportControllerHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "fixture-github-token"
        let firstIssue = harness.makeIssue(
            title: "Frontend issue",
            gitHubExportTarget: GitHubIssueExportTarget(owner: "acme", repository: "frontend", labels: ["ui"])
        )
        let secondIssue = harness.makeIssue(
            title: "Backend issue",
            gitHubExportTarget: GitHubIssueExportTarget(owner: "acme", repository: "backend", labels: ["api"])
        )
        let session = harness.makeSession(issues: [firstIssue, secondIssue])
        try harness.transcriptStore.add(session)

        let context = try harness.requireContext(
            harness.controller.preflightIssueExport(from: session, to: .github, statusPhase: .idle)
        )
        let review = try await harness.controller.prepareIssueExportReview(
            for: context,
            model: "gpt-test",
            apiBaseURL: URL(string: "https://api.example.test")!
        )

        let reviewConfigurations = await harness.exportService.gitHubReviewConfigurations
        XCTAssertEqual(review.items.map(\.issue.title), ["Frontend issue", "Backend issue"])
        XCTAssertEqual(reviewConfigurations.map(\.targetIdentity), ["acme/frontend", "acme/backend"])
        XCTAssertNil(harness.controller.exportDestinationInProgress)
        XCTAssertNil(harness.controller.pendingExportReview)
    }

    /// The export review sends the API key and the issue content to the AI
    /// provider endpoint, so a refused endpoint must not receive them. The
    /// extraction path has always checked this; the export path did not, so a
    /// base URL changed to a plaintext host after the extraction would put the
    /// key on the wire in the clear.
    func testPreflightRefusesWhenTheAIProviderEndpointIsRefused() throws {
        let harness = try IssueExportControllerHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.aiProvider = .openAICompatible
        harness.settingsStore.openAIBaseURL = "http://nas.local/v1"

        let session = harness.makeSession(issues: [harness.makeIssue(title: "App issue")])
        try harness.transcriptStore.add(session)

        let result = harness.controller.preflightIssueExport(from: session, to: .github, statusPhase: .idle)

        guard case .failure(let failure) = result else {
            return XCTFail("expected the export to be refused for a plaintext AI provider endpoint")
        }
        XCTAssertTrue(
            failure.error.userMessage.contains("nas.local"),
            "the refusal has to name the host: \(failure.error.userMessage)"
        )
        XCTAssertTrue(
            failure.opensSettings,
            "the fix is in Settings, so the refusal has to take the user there"
        )
    }

    func testJiraGroupingUsesPerIssueTargets() async throws {
        let harness = try IssueExportControllerHarness()
        defer { harness.cleanup() }

        harness.settingsStore.jiraBaseURL = "https://example.atlassian.net"
        harness.settingsStore.jiraEmail = "jira-user@example.com"
        harness.settingsStore.jiraAPIToken = "fixture-jira-token"
        let firstIssue = harness.makeIssue(
            title: "App issue",
            jiraExportTarget: JiraIssueExportTarget(
                projectID: "10000",
                projectKey: "APP",
                issueTypeID: "10001",
                issueTypeName: "Bug"
            )
        )
        let secondIssue = harness.makeIssue(
            title: "Ops issue",
            jiraExportTarget: JiraIssueExportTarget(
                projectID: "20000",
                projectKey: "OPS",
                issueTypeID: "20001",
                issueTypeName: "Task"
            )
        )
        let session = harness.makeSession(issues: [firstIssue, secondIssue])
        try harness.transcriptStore.add(session)

        let context = try harness.requireContext(
            harness.controller.preflightIssueExport(from: session, to: .jira, statusPhase: .idle)
        )
        _ = try await harness.controller.prepareIssueExportReview(
            for: context,
            model: "gpt-test",
            apiBaseURL: URL(string: "https://api.example.test")!
        )

        let reviewConfigurations = await harness.exportService.jiraReviewConfigurations
        XCTAssertEqual(reviewConfigurations.map(\.targetIdentity), ["10000::10001", "20000::20001"])
        XCTAssertNil(harness.controller.exportDestinationInProgress)
        XCTAssertNil(harness.controller.pendingExportReview)
    }

    func testJiraExportIsRefusedForAPlaintextRemoteBaseURL() async throws {
        let harness = try IssueExportControllerHarness()
        defer { harness.cleanup() }

        // A self-hosted Jira on plain HTTP is common, so the field accepts it.
        // The export must still be refused: the account email, the API token and
        // the issue content would cross the network in the clear.
        harness.settingsStore.jiraBaseURL = "http://jira.example.com"
        harness.settingsStore.jiraEmail = "jira-user@example.com"
        harness.settingsStore.jiraAPIToken = "fixture-jira-token"
        let issue = harness.makeIssue(
            title: "App issue",
            jiraExportTarget: JiraIssueExportTarget(
                projectID: "10000",
                projectKey: "APP",
                issueTypeID: "10001",
                issueTypeName: "Bug"
            )
        )
        let session = harness.makeSession(issues: [issue])
        try harness.transcriptStore.add(session)

        switch harness.controller.preflightIssueExport(from: session, to: .jira, statusPhase: .idle) {
        case .success:
            XCTFail("expected the export to be refused for a plaintext remote Jira URL")
        case .failure(let failure):
            guard case .exportConfigurationIncompatible(let message) = failure.error else {
                return XCTFail("expected an incompatible-configuration error, got \(failure.error)")
            }
            XCTAssertTrue(message.contains("jira.example.com"))
            // The fix lives in Settings, so the failure has to open it.
            XCTAssertTrue(failure.opensSettings)
        }

        // The same configuration is fine over HTTPS.
        harness.settingsStore.jiraBaseURL = "https://jira.example.com"
        let context = try harness.requireContext(
            harness.controller.preflightIssueExport(from: session, to: .jira, statusPhase: .idle)
        )
        XCTAssertEqual(context.destination, .jira)
    }

    func testPendingReviewMutationAndCancel() async throws {
        let harness = try IssueExportControllerHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        let issue = harness.makeIssue(title: "Login issue")
        let session = harness.makeSession(issues: [issue])
        try harness.transcriptStore.add(session)
        await harness.exportService.setGitHubReview(harness.makeReview(for: issue, sessionID: session.id))

        let context = try harness.requireContext(
            harness.controller.preflightIssueExport(from: session, to: .github, statusPhase: .idle)
        )
        _ = try await harness.controller.prepareIssueExportReview(
            for: context,
            model: "gpt-test",
            apiBaseURL: URL(string: "https://api.example.test")!
        )

        XCTAssertNotNil(harness.controller.pendingExportReview)
        harness.controller.setExportReviewResolution(.linkAsRelated, for: issue.id)
        XCTAssertEqual(harness.controller.pendingExportReview?.items.first?.resolution, .linkAsRelated)

        harness.controller.cancelPendingExportReview()
        XCTAssertNil(harness.controller.pendingExportReview)
    }

    func testFinalizeReviewedExportSkipsDuplicateAndClearsPendingReview() async throws {
        let harness = try IssueExportControllerHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        let issue = harness.makeIssue(title: "Duplicate login issue")
        let session = harness.makeSession(issues: [issue])
        try harness.transcriptStore.add(session)
        await harness.exportService.setGitHubReview(harness.makeReview(for: issue, sessionID: session.id))

        let context = try harness.requireContext(
            harness.controller.preflightIssueExport(from: session, to: .github, statusPhase: .idle)
        )
        _ = try await harness.controller.prepareIssueExportReview(
            for: context,
            model: "gpt-test",
            apiBaseURL: URL(string: "https://api.example.test")!
        )
        harness.controller.setExportReviewResolution(.markDuplicate, for: issue.id)

        let review = try XCTUnwrap(harness.controller.pendingExportReview)
        XCTAssertFalse(try harness.controller.pendingReviewRequiresRemoteExport(review))
        let completion = try await harness.controller.finalizeIssueExport(using: review)

        let exportCallCount = await harness.exportService.gitHubCallCount
        XCTAssertEqual(exportCallCount, 0)
        XCTAssertEqual(completion.duplicateCount, 1)
        XCTAssertFalse(completion.performedRemoteExport)
        XCTAssertNil(harness.controller.pendingExportReview)
    }

    func testFinalizeReviewedExportAddsRelatedContextForRemoteExport() async throws {
        let harness = try IssueExportControllerHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        let issue = harness.makeIssue(title: "Related login issue")
        let session = harness.makeSession(issues: [issue])
        try harness.transcriptStore.add(session)
        await harness.exportService.setGitHubReview(harness.makeReview(for: issue, sessionID: session.id))
        await harness.exportService.setGitHubResults([
            ExportResult(
                sourceIssueID: issue.id,
                destination: .github,
                remoteIdentifier: "#200",
                remoteURL: URL(string: "https://github.com/acme/bugnarrator/issues/200")
            )
        ])

        let context = try harness.requireContext(
            harness.controller.preflightIssueExport(from: session, to: .github, statusPhase: .idle)
        )
        _ = try await harness.controller.prepareIssueExportReview(
            for: context,
            model: "gpt-test",
            apiBaseURL: URL(string: "https://api.example.test")!
        )
        harness.controller.setExportReviewResolution(.linkAsRelated, for: issue.id)

        let review = try XCTUnwrap(harness.controller.pendingExportReview)
        XCTAssertTrue(try harness.controller.pendingReviewRequiresRemoteExport(review))
        let completion = try await harness.controller.finalizeIssueExport(using: review)

        let exportedIssues = await harness.exportService.lastGitHubIssues
        XCTAssertTrue(completion.performedRemoteExport)
        XCTAssertEqual(exportedIssues.count, 1)
        XCTAssertTrue(exportedIssues.first?.note?.contains("Related to #142") == true)
    }

    private func makeIssueExportPresentationController(
        status: AppStatus = .idle()
    ) -> (
        presenter: IssueExportPresentationController,
        presentationState: AppPresentationState,
        telemetryRecorder: MockOperationalTelemetryRecorder,
        settingsWindowOpenCount: () -> Int
    ) {
        let presentationState = AppPresentationState(status: status)
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        var settingsWindowOpenCount = 0
        let presenter = IssueExportPresentationController(
            errorPresenter: AppErrorPresenter(
                presentationState: presentationState,
                telemetryRecorder: telemetryRecorder
            ),
            showSettingsWindow: {
                settingsWindowOpenCount += 1
            }
        )

        return (
            presenter: presenter,
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder,
            settingsWindowOpenCount: { settingsWindowOpenCount }
        )
    }
}

@MainActor
private final class IssueExportControllerHarness {
    let rootDirectoryURL: URL
    let defaultsSuiteName: String
    let defaults: UserDefaults
    let settingsStore: SettingsStore
    let transcriptStore: TranscriptStore
    let exportService: MockExportService
    let sessionLibrary: SessionLibraryController
    let controller: IssueExportController

    init() throws {
        let fileManager = FileManager.default
        rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("BugNarratorIssueExportControllerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        defaultsSuiteName = "BugNarratorIssueExportControllerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        settingsStore = Self.makeHermeticSettingsStore(defaults: defaults)
        settingsStore.apiKey = "test-api-key"

        transcriptStore = TranscriptStore(
            fileManager: fileManager,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json")
        )
        exportService = MockExportService()
        sessionLibrary = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts")),
            clipboardService: MockClipboardService()
        )
        controller = IssueExportController(
            settingsStore: settingsStore,
            sessionLibrary: sessionLibrary,
            exportService: exportService
        )
    }

    func makeSession(issues: [ExtractedIssue]) -> TranscriptSession {
        TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 6,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: issues)
        )
    }

    func makeIssue(
        title: String,
        gitHubExportTarget: GitHubIssueExportTarget? = nil,
        jiraExportTarget: JiraIssueExportTarget? = nil
    ) -> ExtractedIssue {
        ExtractedIssue(
            title: title,
            category: .bug,
            summary: "Summary for \(title)",
            evidenceExcerpt: "Evidence for \(title)",
            timestamp: 2,
            requiresReview: true,
            isSelectedForExport: true,
            gitHubExportTarget: gitHubExportTarget,
            jiraExportTarget: jiraExportTarget
        )
    }

    func makeReview(for issue: ExtractedIssue, sessionID: UUID) -> IssueExportReview {
        IssueExportReview(
            destination: .github,
            sessionID: sessionID,
            items: [
                IssueExportReviewItem(
                    issue: issue,
                    matches: [
                        SimilarIssueMatch(
                            remoteIdentifier: "#142",
                            title: "Login form validation broken",
                            summary: "The login form never re-enables its submit button.",
                            remoteURL: URL(string: "https://github.com/acme/bugnarrator/issues/142"),
                            confidence: 0.85,
                            reasoning: "Both reports describe the same blocked login action after valid input."
                        )
                    ]
                )
            ]
        )
    }

    func requireContext(
        _ result: Result<IssueExportRequestContext, IssueExportPreflightFailure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> IssueExportRequestContext {
        switch result {
        case .success(let context):
            return context
        case .failure(let failure):
            XCTFail("Expected export preflight success, got \(failure.error)", file: file, line: line)
            throw failure.error
        }
    }

    private static func makeHermeticSettingsStore(defaults: UserDefaults) -> SettingsStore {
        makeIsolatedSettingsStore(
            defaults: defaults,
            keychainService: MockKeychainService(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}
