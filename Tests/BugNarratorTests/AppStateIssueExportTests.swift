import AppKit
import Combine
import XCTest
@testable import BugNarrator

@MainActor
final class AppStateIssueExportTests: XCTestCase {
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

        XCTAssertFalse(harness.appState.canRequestIssueExport(from: session))
        XCTAssertFalse(harness.appState.canExportIssues(from: session, to: .github))
        XCTAssertNoThrow(try harness.transcriptStore.add(session))
        harness.appState.selectedTranscriptID = session.id

        XCTAssertTrue(harness.appState.canRequestIssueExport(from: session))
        XCTAssertFalse(harness.appState.canExportIssues(from: session, to: .github))
        XCTAssertEqual(
            harness.appState.issueExportSetupMessage(for: .github),
            "GitHub token is missing. Click Set Up GitHub to open Settings."
        )

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        harness.settingsStore.githubRepositoryID = "R_kgDOFixture"

        XCTAssertTrue(harness.appState.canExportIssues(from: session, to: .github))
        XCTAssertNil(harness.appState.issueExportSetupMessage(for: .github))
    }

    func testCanExportIssuesAllowsJiraProjectKeyAndIssueTypeNameWithoutHiddenIDs() {
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

        harness.settingsStore.jiraBaseURL = "https://digitaltransformation-csra.atlassian.net"
        harness.settingsStore.jiraEmail = "jira-user@example.com"
        harness.settingsStore.jiraAPIToken = "fixture-jira-token"
        harness.settingsStore.jiraProjectKey = "UCAP"
        harness.settingsStore.jiraIssueType = "Task"

        XCTAssertTrue(harness.appState.canRequestIssueExport(from: session))
        XCTAssertTrue(harness.appState.canExportIssues(from: session, to: .jira))
        XCTAssertNil(harness.appState.issueExportSetupMessage(for: .jira))
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

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        harness.settingsStore.githubRepositoryID = "R_kgDOFixture"

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

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        harness.settingsStore.githubRepositoryID = "R_kgDOFixture"
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

    func testExportSelectedIssuesUsesPerIssueGitHubTargets() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "fixture-github-token"

        let firstIssue = ExtractedIssue(
            title: "First issue",
            category: .bug,
            summary: "Summary",
            evidenceExcerpt: "Evidence",
            timestamp: 2,
            isSelectedForExport: true,
            gitHubExportTarget: GitHubIssueExportTarget(
                owner: "acme",
                repository: "frontend",
                labels: ["bug", "ui"]
            )
        )
        let secondIssue = ExtractedIssue(
            title: "Second issue",
            category: .bug,
            summary: "Summary",
            evidenceExcerpt: "Evidence",
            timestamp: 3,
            isSelectedForExport: true,
            gitHubExportTarget: GitHubIssueExportTarget(
                owner: "acme",
                repository: "backend",
                labels: ["api"]
            )
        )
        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 6,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [firstIssue, secondIssue])
        )
        XCTAssertNoThrow(try harness.transcriptStore.add(session))
        harness.appState.selectedTranscriptID = session.id

        XCTAssertTrue(harness.appState.canExportIssues(from: session, to: .github))

        await harness.appState.exportSelectedIssues(from: session, to: .github)

        let reviewConfigurations = await harness.exportService.gitHubReviewConfigurations
        let exportConfigurations = await harness.exportService.gitHubExportConfigurations
        let reviewCallCount = await harness.exportService.gitHubReviewCallCount
        let exportCallCount = await harness.exportService.gitHubCallCount

        XCTAssertEqual(reviewCallCount, 2)
        XCTAssertEqual(exportCallCount, 2)
        XCTAssertEqual(reviewConfigurations.map(\.targetIdentity), ["acme/frontend", "acme/backend"])
        XCTAssertEqual(exportConfigurations.map(\.targetIdentity), ["acme/frontend", "acme/backend"])
        XCTAssertEqual(exportConfigurations.first?.labels, ["bug", "ui"])
        XCTAssertEqual(exportConfigurations.last?.labels, ["api"])
    }

    func testExportSelectedIssuesUsesPerIssueJiraTargets() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.jiraBaseURL = "https://example.atlassian.net"
        harness.settingsStore.jiraEmail = "jira-user@example.com"
        harness.settingsStore.jiraAPIToken = "fixture-jira-token"

        let firstIssue = ExtractedIssue(
            title: "First issue",
            category: .bug,
            summary: "Summary",
            evidenceExcerpt: "Evidence",
            timestamp: 2,
            isSelectedForExport: true,
            jiraExportTarget: JiraIssueExportTarget(
                projectID: "10000",
                projectKey: "APP",
                projectName: "App",
                issueTypeID: "10001",
                issueTypeName: "Bug"
            )
        )
        let secondIssue = ExtractedIssue(
            title: "Second issue",
            category: .bug,
            summary: "Summary",
            evidenceExcerpt: "Evidence",
            timestamp: 3,
            isSelectedForExport: true,
            jiraExportTarget: JiraIssueExportTarget(
                projectID: "20000",
                projectKey: "OPS",
                projectName: "Operations",
                issueTypeID: "20001",
                issueTypeName: "Task"
            )
        )
        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 6,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [firstIssue, secondIssue])
        )
        XCTAssertNoThrow(try harness.transcriptStore.add(session))
        harness.appState.selectedTranscriptID = session.id

        XCTAssertTrue(harness.appState.canExportIssues(from: session, to: .jira))

        await harness.appState.exportSelectedIssues(from: session, to: .jira)

        let reviewConfigurations = await harness.exportService.jiraReviewConfigurations
        let exportConfigurations = await harness.exportService.jiraExportConfigurations
        let reviewCallCount = await harness.exportService.jiraReviewCallCount
        let exportCallCount = await harness.exportService.jiraCallCount

        XCTAssertEqual(reviewCallCount, 2)
        XCTAssertEqual(exportCallCount, 2)
        XCTAssertEqual(reviewConfigurations.map(\.targetIdentity), ["10000::10001", "20000::20001"])
        XCTAssertEqual(exportConfigurations.map(\.targetIdentity), ["10000::10001", "20000::20001"])
        XCTAssertEqual(exportConfigurations.first?.projectKey, "APP")
        XCTAssertEqual(exportConfigurations.last?.issueTypeName, "Task")
    }

    func testExportSelectedIssuesPresentsSimilarIssueReviewWhenMatchesExist() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        harness.settingsStore.githubRepositoryID = "R_kgDOFixture"

        let sourceIssue = ExtractedIssue(
            title: "Login button is disabled",
            category: .bug,
            summary: "The login button never enables after valid input.",
            evidenceExcerpt: "The login button stayed disabled after I entered a valid email.",
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
        await harness.exportService.setGitHubReview(
            IssueExportReview(
                destination: .github,
                sessionID: session.id,
                items: [
                    IssueExportReviewItem(
                        issue: sourceIssue,
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
        )

        await harness.appState.exportSelectedIssues(from: session, to: .github)

        let reviewCallCount = await harness.exportService.gitHubReviewCallCount
        let exportCallCount = await harness.exportService.gitHubCallCount
        XCTAssertEqual(reviewCallCount, 1)
        XCTAssertEqual(exportCallCount, 0)
        XCTAssertEqual(harness.appState.pendingExportReview?.items.first?.matches.first?.remoteIdentifier, "#142")
        XCTAssertEqual(harness.appState.status.phase, .success)
    }

    func testConfirmPendingExportReviewSkipsCreatingDuplicateIssue() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        harness.settingsStore.githubRepositoryID = "R_kgDOFixture"

        let sourceIssue = ExtractedIssue(
            title: "Login button is disabled",
            category: .bug,
            summary: "The login button never enables after valid input.",
            evidenceExcerpt: "The login button stayed disabled after I entered a valid email.",
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
        await harness.exportService.setGitHubReview(
            IssueExportReview(
                destination: .github,
                sessionID: session.id,
                items: [
                    IssueExportReviewItem(
                        issue: sourceIssue,
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
        )

        await harness.appState.exportSelectedIssues(from: session, to: .github)
        harness.appState.setExportReviewResolution(.markDuplicate, for: sourceIssue.id)
        await harness.appState.confirmPendingExportReview()

        let exportCallCount = await harness.exportService.gitHubCallCount
        XCTAssertEqual(exportCallCount, 0)
        XCTAssertNil(harness.appState.pendingExportReview)
        XCTAssertEqual(harness.appState.status.phase, .success)
    }

    func testConfirmPendingExportReviewAddsTrackerContextForRelatedLink() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        harness.settingsStore.githubRepositoryID = "R_kgDOFixture"
        await harness.exportService.setGitHubResults([
            ExportResult(
                sourceIssueID: UUID(),
                destination: .github,
                remoteIdentifier: "#200",
                remoteURL: URL(string: "https://github.com/acme/bugnarrator/issues/200")
            )
        ])

        let sourceIssue = ExtractedIssue(
            title: "Login button is disabled",
            category: .bug,
            summary: "The login button never enables after valid input.",
            evidenceExcerpt: "The login button stayed disabled after I entered a valid email.",
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
        await harness.exportService.setGitHubReview(
            IssueExportReview(
                destination: .github,
                sessionID: session.id,
                items: [
                    IssueExportReviewItem(
                        issue: sourceIssue,
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
        )

        await harness.appState.exportSelectedIssues(from: session, to: .github)
        harness.appState.setExportReviewResolution(.linkAsRelated, for: sourceIssue.id)
        await harness.appState.confirmPendingExportReview()

        let exportCallCount = await harness.exportService.gitHubCallCount
        let exportedIssues = await harness.exportService.lastGitHubIssues
        XCTAssertEqual(exportCallCount, 1)
        XCTAssertEqual(exportedIssues.count, 1)
        XCTAssertTrue(exportedIssues.first?.note?.contains("Related to #142") == true)
    }
}
