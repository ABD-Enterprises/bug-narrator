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
        let screenshotURL = makeScreenshotFileURL(named: "review-shot.png")
        let screenshot = SessionScreenshot(elapsedTime: 14, filePath: screenshotURL.path)
        let artifactsDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let issue = ExtractedIssue(
            title: "Login button is disabled",
            category: .bug,
            severity: .high,
            component: "Login Page",
            summary: "The login button stays disabled after valid input.",
            evidenceExcerpt: "The login button never re-enabled after typing a valid email.",
            deduplicationHint: "issue-login-disabled",
            timestamp: 14,
            relatedScreenshotIDs: [screenshot.id],
            requiresReview: true,
            reproductionSteps: [
                IssueReproductionStep(
                    instruction: "Enter a valid email and password.",
                    expectedResult: "The login button enables.",
                    actualResult: "The login button stays disabled.",
                    timestamp: 14
                )
            ],
            screenshotAnnotations: [
                IssueScreenshotAnnotation(
                    screenshotID: screenshot.id,
                    label: "Login button",
                    x: 0.44,
                    y: 0.52,
                    width: 0.24,
                    height: 0.16,
                    confidence: 0.82
                )
            ],
            note: "Related to #142 (85% match): Login form validation broken."
        )
        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 20,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            screenshots: [screenshot],
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [issue]),
            artifactsDirectoryPath: artifactsDirectory.path
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

        let body = try requestBodyData(from: request)
        let payload = try JSONDecoder().decode(GitHubIssueRequestPayload.self, from: body)
        XCTAssertEqual(payload.title, "Login button is disabled")
        XCTAssertEqual(payload.labels, ["bug", "triage"])
        XCTAssertTrue(payload.body.contains("Transcript time"))
        XCTAssertTrue(payload.body.contains("Severity: High"))
        XCTAssertTrue(payload.body.contains("Component: Login Page"))
        XCTAssertTrue(payload.body.contains("Deduplication hint: `issue-login-disabled`"))
        XCTAssertTrue(payload.body.contains("Review needed: Yes"))
        XCTAssertTrue(payload.body.contains("## Tracker Context"))
        XCTAssertTrue(payload.body.contains("Related to #142"))
        XCTAssertTrue(payload.body.contains("## Reproduction Steps"))
        XCTAssertTrue(payload.body.contains("Expected: The login button enables."))
        XCTAssertTrue(payload.body.contains("Actual: The login button stays disabled."))
        XCTAssertTrue(payload.body.contains("## Annotated Screenshots"))
        XCTAssertTrue(payload.body.contains("Login button"))
        XCTAssertTrue(payload.body.contains("review-shot-annotated"))
    }

    func testFindOpenIssuesBuildsSearchRequestAndParsesMatches() async throws {
        let provider = GitHubExportProvider(session: makeMockURLSession())
        let issue = ExtractedIssue(
            title: "Login button is disabled",
            category: .bug,
            summary: "The login button never enables after valid input.",
            evidenceExcerpt: "The login button stayed disabled after I entered a valid email.",
            timestamp: nil
        )

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("/search/issues?") == true)
            XCTAssertTrue(request.url?.absoluteString.contains("repo:acme/bugnarrator") == true)
            XCTAssertTrue(request.url?.absoluteString.contains("is:open") == true)

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(
                #"{"items":[{"number":142,"title":"Login form validation broken","body":"The login form never re-enables its submit button.","html_url":"https://github.com/acme/bugnarrator/issues/142"}]}"#.utf8
            )
            return (response, data)
        }

        let matches = try await provider.findOpenIssues(
            matching: issue,
            configuration: GitHubExportConfiguration(
                token: "fixture-github-token",
                owner: "acme",
                repository: "bugnarrator",
                labels: []
            )
        )

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.remoteIdentifier, "#142")
        XCTAssertEqual(matches.first?.title, "Login form validation broken")
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

private func makeScreenshotFileURL(named fileName: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    let pngData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg=="
    )!
    try? pngData.write(to: url)
    return url
}
