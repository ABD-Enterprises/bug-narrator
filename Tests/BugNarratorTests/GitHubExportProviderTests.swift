import Foundation
import XCTest
@testable import BugNarrator

final class GitHubExportProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testMakeURLRequestIncludesAuthorizationAndIssueBody() async throws {
        let provider = GitHubExportProvider(session: makeMockURLSession())
        let issue = ExtractedIssue(
            title: "Login button is disabled",
            category: .bug,
            severity: .high,
            component: "Login Page",
            summary: "The login button stays disabled after valid input.",
            evidenceExcerpt: "The login button never re-enabled after typing a valid email.",
            deduplicationHint: "issue-login-disabled",
            timestamp: 14,
            relatedScreenshotIDs: [],
            requiresReview: true,
            reproductionSteps: [
                IssueReproductionStep(
                    instruction: "Enter a valid email and password.",
                    expectedResult: "The login button enables.",
                    actualResult: "The login button stays disabled.",
                    timestamp: 14
                )
            ]
        )
        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 20,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [issue])
        )
        let request = try await provider.makeURLRequest(
            issue: issue,
            session: session,
            configuration: GitHubExportConfiguration(
                token: "fixture-github-token",
                owner: "acme",
                repository: "bugnarrator",
                labels: ["bug", "triage"]
            )
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/acme/bugnarrator/issues")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-github-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "BugNarrator")

        let body: Data = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(GitHubIssueRequestPayload.self, from: body)
        XCTAssertEqual(payload.title, "Login button is disabled")
        XCTAssertEqual(payload.labels, ["bug", "triage"])
        XCTAssertTrue(payload.body.contains("Transcript time"))
        XCTAssertTrue(payload.body.contains("Severity: High"))
        XCTAssertTrue(payload.body.contains("Component: Login Page"))
        XCTAssertTrue(payload.body.contains("Deduplication hint: `issue-login-disabled`"))
        XCTAssertTrue(payload.body.contains("Review needed: Yes"))
        XCTAssertTrue(payload.body.contains("## Reproduction Steps"))
        XCTAssertTrue(payload.body.contains("Expected: The login button enables."))
        XCTAssertTrue(payload.body.contains("Actual: The login button stays disabled."))
    }

    func testExportMapsRepositoryNotFound() async throws {
        let provider = GitHubExportProvider(session: makeMockURLSession())
        let issue = ExtractedIssue(
            title: "Issue",
            category: .bug,
            summary: "Summary",
            evidenceExcerpt: "Evidence",
            timestamp: nil
        )
        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 6,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [issue])
        )

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 404, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"message":"Not Found"}"#.utf8)
            return (response, data)
        }

        do {
            _ = try await provider.export(
                issues: [issue],
                session: session,
                configuration: GitHubExportConfiguration(
                    token: "fixture-github-token",
                    owner: "acme",
                    repository: "bugnarrator",
                    labels: []
                )
            )
            XCTFail("Expected export to fail.")
        } catch let error as AppError {
            guard case .exportFailure(let message) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertTrue(message.contains("could not find"))
        }
    }

    func testExportReportsPartialSuccessWhenLaterIssueFails() async throws {
        let provider = GitHubExportProvider(session: makeMockURLSession())
        let firstIssue = ExtractedIssue(
            title: "First issue",
            category: .bug,
            summary: "Summary",
            evidenceExcerpt: "Evidence",
            timestamp: nil
        )
        let secondIssue = ExtractedIssue(
            title: "Second issue",
            category: .bug,
            summary: "Summary",
            evidenceExcerpt: "Evidence",
            timestamp: nil
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

        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: requestCount == 1 ? 201 : 422, httpVersion: nil, headerFields: nil)!
            let data: Data
            if requestCount == 1 {
                data = Data(#"{"number":101,"html_url":"https://github.com/acme/bugnarrator/issues/101"}"#.utf8)
            } else {
                data = Data(#"{"message":"Validation Failed"}"#.utf8)
            }
            return (response, data)
        }

        do {
            _ = try await provider.export(
                issues: [firstIssue, secondIssue],
                session: session,
                configuration: GitHubExportConfiguration(
                    token: "fixture-github-token",
                    owner: "acme",
                    repository: "bugnarrator",
                    labels: []
                )
            )
            XCTFail("Expected export to fail.")
        } catch let error as AppError {
            guard case .exportFailure(let message) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertTrue(message.contains("GitHub exported 1 issue"))
            XCTAssertTrue(message.contains("Validation Failed"))
        }
    }
}

private struct GitHubIssueRequestPayload: Decodable {
    let title: String
    let body: String
    let labels: [String]?
}
