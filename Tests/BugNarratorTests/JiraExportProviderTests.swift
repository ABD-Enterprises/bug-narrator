import Foundation
import XCTest
@testable import BugNarrator

final class JiraExportProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testMakeURLRequestIncludesBasicAuthAndProjectFields() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())
        let issue = ExtractedIssue(
            title: "Modal lacks close affordance",
            category: .uxIssue,
            summary: "The modal has no visible close affordance.",
            evidenceExcerpt: "I cannot tell how to dismiss the modal.",
            timestamp: 22,
            requiresReview: true,
            reproductionSteps: [
                IssueReproductionStep(
                    instruction: "Open the modal from settings.",
                    expectedResult: "A close affordance is visible immediately.",
                    actualResult: "No close affordance appears in the modal chrome.",
                    timestamp: 22
                )
            ]
        )
        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 30,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [issue])
        )
        let request = try await provider.makeURLRequest(
            issue: issue,
            session: session,
            configuration: JiraExportConfiguration(
                baseURL: URL(string: "https://acme.atlassian.net")!,
                email: "you@example.com",
                apiToken: "fixture-jira-token",
                projectKey: "FM",
                issueType: "Task"
            )
        )

        XCTAssertEqual(request.url?.absoluteString, "https://acme.atlassian.net/rest/api/3/issue")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "BugNarrator")

        let body: Data = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let fields = try XCTUnwrap(payload["fields"] as? [String: Any])
        let project = try XCTUnwrap(fields["project"] as? [String: Any])
        let issueType = try XCTUnwrap(fields["issuetype"] as? [String: Any])

        XCTAssertEqual(project["key"] as? String, "FM")
        XCTAssertEqual(issueType["name"] as? String, "Task")
        XCTAssertEqual(fields["summary"] as? String, "Modal lacks close affordance")
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let payloadString = try XCTUnwrap(String(data: payloadData, encoding: .utf8))
        XCTAssertTrue(payloadString.contains("Reproduction steps"))
        XCTAssertTrue(payloadString.contains("Expected: A close affordance is visible immediately."))
        XCTAssertTrue(payloadString.contains("Actual: No close affordance appears in the modal chrome."))
    }

    func testExportMapsValidationFailure() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())
        let issue = ExtractedIssue(
            title: "Issue",
            category: .followUp,
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
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 400, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"errorMessages":["Issue type is invalid"],"errors":{}}"#.utf8)
            return (response, data)
        }

        do {
            _ = try await provider.export(
                issues: [issue],
                session: session,
                configuration: JiraExportConfiguration(
                    baseURL: URL(string: "https://acme.atlassian.net")!,
                    email: "you@example.com",
                    apiToken: "fixture-jira-token",
                    projectKey: "FM",
                    issueType: "Task"
                )
            )
            XCTFail("Expected export to fail.")
        } catch let error as AppError {
            guard case .exportFailure(let message) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertTrue(message.contains("Issue type is invalid"))
        }
    }

    func testExportReportsPartialSuccessWhenLaterIssueFails() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())
        let firstIssue = ExtractedIssue(
            title: "First issue",
            category: .followUp,
            summary: "Summary",
            evidenceExcerpt: "Evidence",
            timestamp: nil
        )
        let secondIssue = ExtractedIssue(
            title: "Second issue",
            category: .followUp,
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
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: requestCount == 1 ? 201 : 400, httpVersion: nil, headerFields: nil)!
            let data: Data
            if requestCount == 1 {
                data = Data(#"{"id":"10001","key":"FM-101"}"#.utf8)
            } else {
                data = Data(#"{"errorMessages":["Issue type is invalid"],"errors":{}}"#.utf8)
            }
            return (response, data)
        }

        do {
            _ = try await provider.export(
                issues: [firstIssue, secondIssue],
                session: session,
                configuration: JiraExportConfiguration(
                    baseURL: URL(string: "https://acme.atlassian.net")!,
                    email: "you@example.com",
                    apiToken: "fixture-jira-token",
                    projectKey: "FM",
                    issueType: "Task"
                )
            )
            XCTFail("Expected export to fail.")
        } catch let error as AppError {
            guard case .exportFailure(let message) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertTrue(message.contains("Jira exported 1 issue"))
            XCTAssertTrue(message.contains("Issue type is invalid"))
        }
    }
}
