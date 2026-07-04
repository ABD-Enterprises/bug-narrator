import Foundation
import XCTest
@testable import BugNarrator

actor MockIssueExtractionService: IssueExtracting {
    var result = IssueExtractionResult(summary: "", issues: [])

    func setResult(_ result: IssueExtractionResult) {
        self.result = result
    }

    func extractIssues(
        from reviewSession: TranscriptSession,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExtractionResult {
        result
    }
}

actor MockExportService: IssueExporting {
    var gitHubResults: [ExportResult] = []
    var jiraResults: [ExportResult] = []
    var gitHubReview: IssueExportReview?
    var jiraReview: IssueExportReview?
    var exportReceipts: [ExportReceipt] = []
    var gitHubError: Error?
    var jiraError: Error?
    var gitHubRepositories: [GitHubRepositoryOption] = []
    var jiraProjects: [JiraProjectOption] = []
    var jiraIssueTypesByProjectKey: [String: [JiraIssueTypeOption]] = [:]
    var suspendJiraIssueTypeFetch = false

    private(set) var gitHubCallCount = 0
    private(set) var jiraCallCount = 0
    private(set) var gitHubReviewCallCount = 0
    private(set) var jiraReviewCallCount = 0
    private(set) var gitHubValidationCallCount = 0
    private(set) var jiraValidationCallCount = 0
    private(set) var gitHubRepositoryFetchCallCount = 0
    private(set) var jiraProjectFetchCallCount = 0
    private(set) var jiraIssueTypeFetchCallCount = 0
    private(set) var lastGitHubIssues: [ExtractedIssue] = []
    private(set) var lastJiraIssues: [ExtractedIssue] = []
    private(set) var gitHubReviewConfigurations: [GitHubExportConfiguration] = []
    private(set) var jiraReviewConfigurations: [JiraExportConfiguration] = []
    private(set) var gitHubExportConfigurations: [GitHubExportConfiguration] = []
    private(set) var jiraExportConfigurations: [JiraExportConfiguration] = []
    private var gitHubValidationError: Error?
    private var jiraValidationError: Error?
    private var gitHubRepositoriesError: Error?
    private var jiraProjectsError: Error?
    private var jiraIssueTypesError: Error?
    private var jiraIssueTypeFetchContinuations: [(projectKey: String, continuation: CheckedContinuation<[JiraIssueTypeOption], Error>)] = []

    func setGitHubResults(_ results: [ExportResult]) {
        gitHubResults = results
    }

    func setJiraResults(_ results: [ExportResult]) {
        jiraResults = results
    }

    func setGitHubError(_ error: Error?) {
        gitHubError = error
    }

    func setJiraError(_ error: Error?) {
        jiraError = error
    }

    func setGitHubReview(_ review: IssueExportReview) {
        gitHubReview = review
    }

    func setJiraReview(_ review: IssueExportReview) {
        jiraReview = review
    }

    func setGitHubValidationError(_ error: Error?) {
        gitHubValidationError = error
    }

    func setJiraValidationError(_ error: Error?) {
        jiraValidationError = error
    }

    func setGitHubRepositories(_ repositories: [GitHubRepositoryOption]) {
        gitHubRepositories = repositories
    }

    func setExportReceipts(_ receipts: [ExportReceipt]) {
        exportReceipts = receipts
    }

    func setGitHubRepositoriesError(_ error: Error?) {
        gitHubRepositoriesError = error
    }

    func setJiraProjects(_ projects: [JiraProjectOption]) {
        jiraProjects = projects
    }

    func setJiraIssueTypes(_ issueTypes: [JiraIssueTypeOption], for projectKey: String) {
        jiraIssueTypesByProjectKey[projectKey] = issueTypes
    }

    func setJiraProjectsError(_ error: Error?) {
        jiraProjectsError = error
    }

    func setJiraIssueTypesError(_ error: Error?) {
        jiraIssueTypesError = error
    }

    func setSuspendJiraIssueTypeFetch(_ shouldSuspend: Bool) {
        suspendJiraIssueTypeFetch = shouldSuspend
    }

    func jiraIssueTypeFetchCount() -> Int {
        jiraIssueTypeFetchCallCount
    }

    func fetchGitHubRepositories(
        token: String
    ) async throws -> [GitHubRepositoryOption] {
        gitHubRepositoryFetchCallCount += 1

        if let gitHubRepositoriesError {
            throw gitHubRepositoriesError
        }

        return gitHubRepositories
    }

    func fetchJiraProjects(
        _ configuration: JiraConnectionConfiguration
    ) async throws -> [JiraProjectOption] {
        jiraProjectFetchCallCount += 1

        if let jiraProjectsError {
            throw jiraProjectsError
        }

        return jiraProjects
    }

    func fetchJiraIssueTypes(
        for projectKey: String,
        projectID: String?,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraIssueTypeOption] {
        jiraIssueTypeFetchCallCount += 1

        if suspendJiraIssueTypeFetch {
            return try await withCheckedThrowingContinuation { continuation in
                jiraIssueTypeFetchContinuations.append((projectKey: projectKey, continuation: continuation))
            }
        }

        if let jiraIssueTypesError {
            throw jiraIssueTypesError
        }

        return jiraIssueTypesByProjectKey[projectKey] ?? []
    }

    func resumeJiraIssueTypeFetch(
        for projectKey: String,
        with result: Result<[JiraIssueTypeOption], Error>
    ) {
        guard let index = jiraIssueTypeFetchContinuations.firstIndex(where: { $0.projectKey == projectKey }) else {
            return
        }

        let continuation = jiraIssueTypeFetchContinuations.remove(at: index).continuation
        switch result {
        case .success(let issueTypes):
            continuation.resume(returning: issueTypes)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    func validateGitHubConfiguration(
        _ configuration: GitHubExportConfiguration
    ) async throws {
        gitHubValidationCallCount += 1

        if let gitHubValidationError {
            throw gitHubValidationError
        }
    }

    func validateJiraConfiguration(
        _ configuration: JiraExportConfiguration
    ) async throws {
        jiraValidationCallCount += 1

        if let jiraValidationError {
            throw jiraValidationError
        }
    }

    func prepareGitHubExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExportReview {
        gitHubReviewCallCount += 1
        gitHubReviewConfigurations.append(configuration)

        if let gitHubError {
            throw gitHubError
        }

        return gitHubReview ?? IssueExportReview(
            destination: .github,
            sessionID: session.id,
            items: issues.map { IssueExportReviewItem(issue: $0, matches: []) }
        )
    }

    func prepareJiraExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExportReview {
        jiraReviewCallCount += 1
        jiraReviewConfigurations.append(configuration)

        if let jiraError {
            throw jiraError
        }

        return jiraReview ?? IssueExportReview(
            destination: .jira,
            sessionID: session.id,
            items: issues.map { IssueExportReviewItem(issue: $0, matches: []) }
        )
    }

    func exportToGitHub(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration
    ) async throws -> [ExportResult] {
        gitHubCallCount += 1
        lastGitHubIssues = issues
        gitHubExportConfigurations.append(configuration)

        if let gitHubError {
            throw gitHubError
        }

        return gitHubResults
    }

    func exportToJira(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration
    ) async throws -> [ExportResult] {
        jiraCallCount += 1
        lastJiraIssues = issues
        jiraExportConfigurations.append(configuration)

        if let jiraError {
            throw jiraError
        }

        return jiraResults
    }

    func exportHistory() async throws -> [ExportReceipt] {
        exportReceipts
    }
}

func makeSampleTranscriptSession(index: Int) -> TranscriptSession {
    TranscriptSession(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: TimeInterval(index * 60)),
        transcript: "Transcript \(index)",
        duration: TimeInterval(index),
        model: "whisper-1",
        languageHint: nil,
        prompt: nil
    )
}

func waitUntil(
    timeoutNanoseconds: UInt64 = 500_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() {
            return
        }

        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
}

/// In-memory `ExportReceiptStoring` for tests that need to drive the receipt
/// lifecycle — e.g. seeding a `.pending` receipt to exercise the reconcile
/// path — without the file-backed production store. Records `markSucceeded`
/// calls so a test can assert reconciliation occurred.
actor StubExportReceiptStore: ExportReceiptStoring {
    private(set) var receipts: [String: ExportReceipt] = [:]
    private(set) var markSucceededCalls: [(fingerprint: String, remoteIdentifier: String)] = []

    func seedPending(
        fingerprint: String,
        sourceIssueID: UUID,
        destination: ExportDestination,
        targetIdentity: String
    ) {
        receipts[fingerprint] = ExportReceipt(
            fingerprint: fingerprint,
            sourceIssueID: sourceIssueID,
            destination: destination,
            targetIdentity: targetIdentity,
            state: .pending,
            remoteIdentifier: nil,
            remoteURL: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func receipt(for fingerprint: String) async throws -> ExportReceipt? {
        receipts[fingerprint]
    }

    func allReceipts() async throws -> [ExportReceipt] {
        Array(receipts.values)
    }

    func markPending(
        fingerprint: String,
        sourceIssueID: UUID,
        destination: ExportDestination,
        targetIdentity: String
    ) async throws {
        receipts[fingerprint] = ExportReceipt(
            fingerprint: fingerprint,
            sourceIssueID: sourceIssueID,
            destination: destination,
            targetIdentity: targetIdentity,
            state: .pending,
            remoteIdentifier: nil,
            remoteURL: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func markSucceeded(
        fingerprint: String,
        sourceIssueID: UUID,
        destination: ExportDestination,
        targetIdentity: String,
        remoteIdentifier: String,
        remoteURL: URL?
    ) async throws {
        markSucceededCalls.append((fingerprint, remoteIdentifier))
        receipts[fingerprint] = ExportReceipt(
            fingerprint: fingerprint,
            sourceIssueID: sourceIssueID,
            destination: destination,
            targetIdentity: targetIdentity,
            state: .succeeded,
            remoteIdentifier: remoteIdentifier,
            remoteURL: remoteURL,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func clearReceipt(for fingerprint: String) async throws {
        receipts.removeValue(forKey: fingerprint)
    }
}

func requestBodyData(from request: URLRequest) throws -> Data {
    if let httpBody = request.httpBody {
        return httpBody
    }

    guard let stream = request.httpBodyStream else {
        throw NSError(domain: "BugNarratorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Request body was missing."])
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: bufferSize)
        if readCount < 0 {
            throw stream.streamError ?? NSError(
                domain: "BugNarratorTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Request body stream could not be read."]
            )
        }

        if readCount == 0 {
            break
        }

        data.append(buffer, count: readCount)
    }

    return data
}
