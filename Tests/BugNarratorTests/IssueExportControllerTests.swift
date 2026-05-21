import XCTest
@testable import BugNarrator

@MainActor
final class IssueExportControllerTests: XCTestCase {
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

        settingsStore = SettingsStore(
            defaults: defaults,
            keychainService: MockKeychainService(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
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

    func cleanup() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}
