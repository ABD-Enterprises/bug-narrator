import Combine
import Foundation

enum IssueExportStatusPresenter {
    static func reviewPreparationStatus(destination: ExportDestination) -> AppStatus {
        .transcribing("Checking \(destination.rawValue) for similar open issues...")
    }

    static func reviewReadyStatus(destination: ExportDestination) -> AppStatus {
        .success("Review the similar \(destination.rawValue) issues before export.")
    }

    static func remoteExportStatus(destination: ExportDestination) -> AppStatus {
        .transcribing("Exporting reviewed issues to \(destination.rawValue)...")
    }

    static func completionStatus(_ completion: IssueExportCompletion) -> AppStatus {
        .success(completion.summary)
    }
}

@MainActor
final class IssueExportPresentationController {
    private let errorPresenter: AppErrorPresenter
    private let showSettingsWindow: () -> Void

    init(
        errorPresenter: AppErrorPresenter,
        showSettingsWindow: @escaping () -> Void
    ) {
        self.errorPresenter = errorPresenter
        self.showSettingsWindow = showSettingsWindow
    }

    func presentPreflightFailure(_ failure: IssueExportPreflightFailure) {
        let result = presentExportError(failure.error)
        if failure.opensSettings || result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
    }

    func presentReviewPreparation(destination: ExportDestination) {
        errorPresenter.setStatus(IssueExportStatusPresenter.reviewPreparationStatus(destination: destination))
    }

    func presentReviewReady(destination: ExportDestination) {
        errorPresenter.setStatus(IssueExportStatusPresenter.reviewReadyStatus(destination: destination))
    }

    func presentRemoteExportStarted(destination: ExportDestination) {
        errorPresenter.setStatus(IssueExportStatusPresenter.remoteExportStatus(destination: destination))
    }

    func presentCompletion(_ completion: IssueExportCompletion) {
        errorPresenter.setStatus(IssueExportStatusPresenter.completionStatus(completion))
    }

    @discardableResult
    func presentFailure(_ error: Error) -> AppErrorPresentationResult {
        let result = presentExportError(error)
        if result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
        return result
    }

    private func presentExportError(_ error: Error) -> AppErrorPresentationResult {
        errorPresenter.presentError(error, operation: .export, fallback: { .exportFailure($0) })
    }
}

@MainActor
final class IssueExportController: ObservableObject {
    @Published private(set) var exportDestinationInProgress: ExportDestination?
    @Published private(set) var pendingExportReview: IssueExportReview?

    private let settingsStore: SettingsStore
    private let sessionLibrary: SessionLibraryController
    private let exportService: any IssueExporting
    private let logger: DiagnosticsLogger

    init(
        settingsStore: SettingsStore,
        sessionLibrary: SessionLibraryController,
        exportService: any IssueExporting,
        logger: DiagnosticsLogger = DiagnosticsLogger(category: .export)
    ) {
        self.settingsStore = settingsStore
        self.sessionLibrary = sessionLibrary
        self.exportService = exportService
        self.logger = logger
    }

    func isExporting(to destination: ExportDestination) -> Bool {
        exportDestinationInProgress == destination
    }

    func clearProgress() {
        exportDestinationInProgress = nil
    }

    func canRequestIssueExport(
        from session: TranscriptSession,
        statusPhase: AppStatus.Phase
    ) -> Bool {
        guard statusPhase != .recording,
              statusPhase != .transcribing,
              pendingExportReview == nil,
              let session = sessionLibrary.sessionSnapshot(with: session.id),
              let extraction = session.issueExtraction,
              !extraction.selectedIssues.isEmpty else {
            return false
        }

        return true
    }

    func canExportIssues(
        from session: TranscriptSession,
        to destination: ExportDestination,
        statusPhase: AppStatus.Phase
    ) -> Bool {
        guard canRequestIssueExport(from: session, statusPhase: statusPhase),
              let selectedIssues = sessionLibrary.sessionSnapshot(with: session.id)?.issueExtraction?.selectedIssues else {
            return false
        }

        switch destination {
        case .github:
            return (try? configuredGitHubIssueGroups(for: selectedIssues)) != nil
        case .jira:
            return (try? configuredJiraIssueGroups(for: selectedIssues)) != nil
        }
    }

    func issueExportSetupMessage(for destination: ExportDestination) -> String? {
        switch destination {
        case .github:
            guard !settingsStore.hasGitHubToken else {
                return nil
            }
            return "GitHub token is missing. Click Set Up GitHub to open Settings."
        case .jira:
            guard settingsStore.jiraConnectionConfiguration == nil else {
                return nil
            }
            return "Jira connection is missing. Click Set Up Jira to open Settings."
        }
    }

    func issueExportRoutingMessage(
        for destination: ExportDestination,
        session: TranscriptSession
    ) -> String? {
        guard let selectedIssues = sessionLibrary.sessionSnapshot(with: session.id)?.issueExtraction?.selectedIssues,
              !selectedIssues.isEmpty else {
            return nil
        }

        switch destination {
        case .github:
            guard settingsStore.hasGitHubToken else {
                return nil
            }

            let missingCount = selectedIssues.filter { gitHubExportConfiguration(for: $0) == nil }.count
            guard missingCount > 0 else {
                return nil
            }
            return "Choose a GitHub repository for \(missingCount) selected issue\(missingCount == 1 ? "" : "s")."
        case .jira:
            guard settingsStore.jiraConnectionConfiguration != nil else {
                return nil
            }

            let missingCount = selectedIssues.filter { jiraExportConfiguration(for: $0) == nil }.count
            guard missingCount > 0 else {
                return nil
            }
            return "Choose a Jira project and issue type for \(missingCount) selected issue\(missingCount == 1 ? "" : "s")."
        }
    }

    func defaultGitHubIssueExportTarget() -> GitHubIssueExportTarget? {
        guard !settingsStore.normalizedGitHubRepositoryOwner.isEmpty,
              !settingsStore.normalizedGitHubRepositoryName.isEmpty else {
            return nil
        }

        return GitHubIssueExportTarget(
            repositoryID: settingsStore.normalizedGitHubRepositoryID.nilIfEmpty,
            owner: settingsStore.normalizedGitHubRepositoryOwner,
            repository: settingsStore.normalizedGitHubRepositoryName,
            labels: settingsStore.githubDefaultLabelsList
        )
    }

    func defaultJiraIssueExportTarget() -> JiraIssueExportTarget? {
        guard !settingsStore.normalizedJiraProjectKey.isEmpty else {
            return nil
        }

        return JiraIssueExportTarget(
            projectID: settingsStore.normalizedJiraProjectID.nilIfEmpty,
            projectKey: settingsStore.normalizedJiraProjectKey,
            issueTypeID: settingsStore.normalizedJiraIssueTypeID,
            issueTypeName: settingsStore.normalizedJiraIssueType
        )
    }

    func preflightIssueExport(
        from session: TranscriptSession,
        to destination: ExportDestination,
        statusPhase: AppStatus.Phase
    ) -> Result<IssueExportRequestContext, IssueExportPreflightFailure> {
        guard statusPhase != .recording, statusPhase != .transcribing else {
            return .failure(IssueExportPreflightFailure(
                error: .exportFailure("Finish the current background work before exporting issues."),
                opensSettings: false
            ))
        }

        guard let currentSession = sessionLibrary.sessionSnapshot(with: session.id) else {
            return .failure(IssueExportPreflightFailure(
                error: .exportFailure("This session is no longer available in the library."),
                opensSettings: false
            ))
        }

        guard let extraction = currentSession.issueExtraction else {
            return .failure(IssueExportPreflightFailure(
                error: .exportFailure("Run issue extraction before exporting."),
                opensSettings: false
            ))
        }

        let selectedIssues = extraction.selectedIssues
        guard !selectedIssues.isEmpty else {
            return .failure(IssueExportPreflightFailure(
                error: .exportFailure("Select at least one extracted issue to export."),
                opensSettings: false
            ))
        }

        settingsStore.refreshExportSecretsForUserInitiatedAccess()

        do {
            try validateExportConfiguration(for: destination)
        } catch {
            let appError = (error as? AppError) ?? .exportFailure(error.localizedDescription)
            let opensSettings: Bool
            if case .exportConfigurationMissing = appError {
                opensSettings = true
            } else {
                opensSettings = false
            }

            return .failure(IssueExportPreflightFailure(
                error: appError,
                opensSettings: opensSettings
            ))
        }

        guard let apiKey = settingsStore.aiProviderCredentialForUserInitiatedAccess() else {
            return .failure(IssueExportPreflightFailure(error: .missingAPIKey, opensSettings: false))
        }

        return .success(IssueExportRequestContext(
            destination: destination,
            session: currentSession,
            selectedIssues: selectedIssues,
            apiKey: apiKey
        ))
    }

    func prepareIssueExportReview(
        for context: IssueExportRequestContext,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExportReview {
        exportDestinationInProgress = context.destination
        defer { exportDestinationInProgress = nil }

        logger.info(
            "issue_export_review_requested",
            "Preparing similar issue review before export.",
            metadata: [
                "destination": context.destination.rawValue,
                "session_id": context.session.id.uuidString,
                "issue_count": "\(context.selectedIssues.count)"
            ]
        )

        let review: IssueExportReview
        switch context.destination {
        case .github:
            var items: [IssueExportReviewItem] = []
            for group in try configuredGitHubIssueGroups(for: context.selectedIssues) {
                try await exportService.validateGitHubConfiguration(group.configuration)
                let groupReview = try await exportService.prepareGitHubExportReview(
                    issues: group.issues,
                    session: context.session,
                    configuration: group.configuration,
                    apiKey: context.apiKey,
                    model: model,
                    apiBaseURL: apiBaseURL
                )
                items.append(contentsOf: groupReview.items)
            }
            review = IssueExportReview(destination: .github, sessionID: context.session.id, items: items)
        case .jira:
            var items: [IssueExportReviewItem] = []
            for group in try configuredJiraIssueGroups(for: context.selectedIssues) {
                try await exportService.validateJiraConfiguration(group.configuration)
                let groupReview = try await exportService.prepareJiraExportReview(
                    issues: group.issues,
                    session: context.session,
                    configuration: group.configuration,
                    apiKey: context.apiKey,
                    model: model,
                    apiBaseURL: apiBaseURL
                )
                items.append(contentsOf: groupReview.items)
            }
            review = IssueExportReview(destination: .jira, sessionID: context.session.id, items: items)
        }

        if review.hasMatches {
            pendingExportReview = review
            logger.info(
                "issue_export_review_ready",
                "Similar issue review is ready for user confirmation.",
                metadata: [
                    "destination": context.destination.rawValue,
                    "session_id": context.session.id.uuidString
                ]
            )
        }

        return review
    }

    func cancelPendingExportReview() {
        pendingExportReview = nil
    }

    func setExportReviewResolution(_ resolution: SimilarIssueResolution, for issueID: UUID) {
        guard var review = pendingExportReview,
              let itemIndex = review.items.firstIndex(where: { $0.issue.id == issueID }) else {
            return
        }

        review.items[itemIndex].setResolution(resolution)
        pendingExportReview = review
    }

    func selectExportReviewMatch(_ matchID: String, for issueID: UUID) {
        guard var review = pendingExportReview,
              let itemIndex = review.items.firstIndex(where: { $0.issue.id == issueID }) else {
            return
        }

        review.items[itemIndex].selectMatch(id: matchID)
        pendingExportReview = review
    }

    func pendingReviewRequiresRemoteExport(_ review: IssueExportReview) throws -> Bool {
        try !IssueExportReviewPolicy.preparedIssues(from: review).isEmpty
    }

    func finalizeIssueExport(using review: IssueExportReview) async throws -> IssueExportCompletion {
        guard let currentSession = sessionLibrary.sessionSnapshot(with: review.sessionID) else {
            pendingExportReview = nil
            throw AppError.exportFailure("This session is no longer available in the library.")
        }

        let preparedIssues = try IssueExportReviewPolicy.preparedIssues(from: review)
        let duplicateMatches = try IssueExportReviewPolicy.duplicateMatchResults(from: review)

        pendingExportReview = nil
        let combinedResults: [ExportResult]
        var performedRemoteExport = false

        if preparedIssues.isEmpty {
            combinedResults = duplicateMatches
        } else {
            exportDestinationInProgress = review.destination
            defer { exportDestinationInProgress = nil }

            let exportedResults: [ExportResult]
            switch review.destination {
            case .github:
                var results: [ExportResult] = []
                for group in try configuredGitHubIssueGroups(for: preparedIssues) {
                    results += try await exportService.exportToGitHub(
                        issues: group.issues,
                        session: currentSession,
                        configuration: group.configuration
                    )
                }
                exportedResults = results
            case .jira:
                var results: [ExportResult] = []
                for group in try configuredJiraIssueGroups(for: preparedIssues) {
                    results += try await exportService.exportToJira(
                        issues: group.issues,
                        session: currentSession,
                        configuration: group.configuration
                    )
                }
                exportedResults = results
            }

            performedRemoteExport = true
            combinedResults = exportedResults + duplicateMatches
        }

        logger.info(
            "issue_export_completed",
            "Finished exporting selected issues.",
            metadata: [
                "destination": review.destination.rawValue,
                "session_id": currentSession.id.uuidString,
                "issue_count": "\(combinedResults.count)"
            ]
        )

        return IssueExportCompletion(
            destination: review.destination,
            sessionID: currentSession.id,
            results: combinedResults,
            duplicateCount: duplicateMatches.count,
            performedRemoteExport: performedRemoteExport
        )
    }

    private func configuredGitHubIssueGroups(
        for issues: [ExtractedIssue]
    ) throws -> [(configuration: GitHubExportConfiguration, issues: [ExtractedIssue])] {
        var groups: [(configuration: GitHubExportConfiguration, issues: [ExtractedIssue])] = []

        for issue in issues {
            guard let configuration = gitHubExportConfiguration(for: issue) else {
                throw AppError.exportConfigurationMissing(
                    "Choose a GitHub repository for every selected issue before exporting."
                )
            }

            if let groupIndex = groups.firstIndex(where: { $0.configuration == configuration }) {
                groups[groupIndex].issues.append(issue)
            } else {
                groups.append((configuration: configuration, issues: [issue]))
            }
        }

        return groups
    }

    private func configuredJiraIssueGroups(
        for issues: [ExtractedIssue]
    ) throws -> [(configuration: JiraExportConfiguration, issues: [ExtractedIssue])] {
        var groups: [(configuration: JiraExportConfiguration, issues: [ExtractedIssue])] = []

        for issue in issues {
            guard let configuration = jiraExportConfiguration(for: issue) else {
                throw AppError.exportConfigurationMissing(
                    "Choose a Jira project and issue type for every selected issue before exporting."
                )
            }

            if let groupIndex = groups.firstIndex(where: { $0.configuration == configuration }) {
                groups[groupIndex].issues.append(issue)
            } else {
                groups.append((configuration: configuration, issues: [issue]))
            }
        }

        return groups
    }

    private func validateExportConfiguration(for destination: ExportDestination) throws {
        switch destination {
        case .github:
            guard settingsStore.hasGitHubToken else {
                throw AppError.exportConfigurationMissing(
                    "GitHub export requires a personal access token."
                )
            }
        case .jira:
            guard settingsStore.jiraConnectionConfiguration != nil else {
                throw AppError.exportConfigurationMissing(
                    "Jira export requires a base URL, email, and API token."
                )
            }
        }
    }

    private func gitHubExportConfiguration(for issue: ExtractedIssue) -> GitHubExportConfiguration? {
        guard settingsStore.hasGitHubToken else {
            return nil
        }

        let target = issue.gitHubExportTarget ?? defaultGitHubIssueExportTarget()
        guard let target, target.isComplete else {
            return nil
        }

        return GitHubExportConfiguration(
            token: settingsStore.trimmedGitHubToken,
            repositoryID: target.repositoryID,
            owner: target.owner,
            repository: target.repository,
            labels: target.labels
        )
    }

    private func jiraExportConfiguration(for issue: ExtractedIssue) -> JiraExportConfiguration? {
        guard let connection = settingsStore.jiraConnectionConfiguration else {
            return nil
        }

        let target = issue.jiraExportTarget ?? defaultJiraIssueExportTarget()
        guard let target, target.isComplete else {
            return nil
        }

        return JiraExportConfiguration(
            baseURL: connection.baseURL,
            email: connection.email,
            apiToken: connection.apiToken,
            projectID: target.projectID,
            projectKey: target.projectKey,
            issueTypeID: target.issueTypeID,
            issueTypeName: target.issueTypeName
        )
    }
}
