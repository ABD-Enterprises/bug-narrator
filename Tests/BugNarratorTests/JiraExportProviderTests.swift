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
        let screenshotURL = makeScreenshotFileURL(named: "modal-shot.png")
        let screenshot = SessionScreenshot(elapsedTime: 22, filePath: screenshotURL.path)
        let artifactsDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let issue = ExtractedIssue(
            title: "Modal lacks close affordance",
            category: .uxIssue,
            severity: .medium,
            component: "Settings Modal",
            summary: "The modal has no visible close affordance.",
            evidenceExcerpt: "I cannot tell how to dismiss the modal.",
            deduplicationHint: "issue-modal-close-affordance",
            timestamp: 22,
            relatedScreenshotIDs: [screenshot.id],
            requiresReview: true,
            reproductionSteps: [
                IssueReproductionStep(
                    instruction: "Open the modal from settings.",
                    expectedResult: "A close affordance is visible immediately.",
                    actualResult: "No close affordance appears in the modal chrome.",
                    timestamp: 22
                )
            ],
            screenshotAnnotations: [
                IssueScreenshotAnnotation(
                    screenshotID: screenshot.id,
                    label: "Modal close affordance",
                    x: 0.78,
                    y: 0.12,
                    width: 0.14,
                    height: 0.16
                )
            ],
            note: "Related to FM-142 (78% match): Existing modal close affordance issue."
        )
        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 30,
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

        let body = try requestBodyData(from: request)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let fields = try XCTUnwrap(payload["fields"] as? [String: Any])
        let project = try XCTUnwrap(fields["project"] as? [String: Any])
        let issueType = try XCTUnwrap(fields["issuetype"] as? [String: Any])

        XCTAssertEqual(project["key"] as? String, "FM")
        XCTAssertEqual(issueType["name"] as? String, "Task")
        XCTAssertEqual(fields["summary"] as? String, "Modal lacks close affordance")
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let payloadString = try XCTUnwrap(String(data: payloadData, encoding: .utf8))
        XCTAssertTrue(payloadString.contains("Severity: Medium"))
        XCTAssertTrue(payloadString.contains("Component: Settings Modal"))
        XCTAssertTrue(payloadString.contains("Deduplication hint: issue-modal-close-affordance"))
        XCTAssertTrue(payloadString.contains("Tracker context: Related to FM-142"))
        XCTAssertTrue(payloadString.contains("Reproduction steps"))
        XCTAssertTrue(payloadString.contains("Expected: A close affordance is visible immediately."))
        XCTAssertTrue(payloadString.contains("Actual: No close affordance appears in the modal chrome."))
        XCTAssertTrue(payloadString.contains("Annotated screenshots"))
        XCTAssertTrue(payloadString.contains("Modal close affordance"))
        XCTAssertTrue(payloadString.contains("modal-shot-annotated"))
    }

    func testMakeURLRequestPreservesExportFingerprintWhenDescriptionIsTruncated() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())
        let marker = TrackerExportFingerprint.marker(for: "bnexp-fixture")
        let issue = ExtractedIssue(
            title: "Oversized issue",
            category: .bug,
            summary: String(repeating: "Summary ", count: 10_000),
            evidenceExcerpt: String(repeating: "Evidence ", count: 10_000),
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

        let request = try await provider.makeURLRequest(
            issue: issue,
            session: session,
            configuration: JiraExportConfiguration(
                baseURL: URL(string: "https://acme.atlassian.net")!,
                email: "you@example.com",
                apiToken: "fixture-jira-token",
                projectKey: "FM",
                issueType: "Task"
            ),
            exportFingerprint: "bnexp-fixture"
        )

        let body = try requestBodyData(from: request)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let fields = try XCTUnwrap(payload["fields"] as? [String: Any])
        let description = try XCTUnwrap(fields["description"] as? [String: Any])
        let payloadData = try JSONSerialization.data(withJSONObject: description, options: [.sortedKeys])
        let payloadString = try XCTUnwrap(String(data: payloadData, encoding: .utf8))
        XCTAssertLessThanOrEqual(payloadString.count, TrackerExportPayloadBudget.jiraTextLimit + 1_000)
        XCTAssertTrue(payloadString.contains(marker))
    }

    func testMakeURLRequestEncodesIssueTypeNameWhenIDIsUnavailable() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())
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

        let body = try requestBodyData(from: request)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let fields = try XCTUnwrap(payload["fields"] as? [String: Any])
        let issueType = try XCTUnwrap(fields["issuetype"] as? [String: Any])
        XCTAssertNil(issueType["id"])
        XCTAssertEqual(issueType["name"] as? String, "Task")
    }

    func testFindOpenIssuesBuildsSearchRequestAndParsesMatches() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())
        let issue = ExtractedIssue(
            title: "Modal lacks close affordance",
            category: .uxIssue,
            summary: "The modal has no visible close affordance.",
            evidenceExcerpt: "I cannot tell how to dismiss the modal.",
            timestamp: nil
        )

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://acme.atlassian.net/rest/api/3/search/jql")
            let body = try requestBodyData(from: request)
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertTrue((payload["jql"] as? String)?.contains("project = FM") == true)
            XCTAssertEqual(payload["maxResults"] as? Int, 5)

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(
                #"{"issues":[{"key":"FM-142","fields":{"summary":"Existing modal close affordance issue","description":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"The modal cannot be dismissed quickly."}]}]}}}]}"#.utf8
            )
            return (response, data)
        }

        let matches = try await provider.findOpenIssues(
            matching: issue,
            configuration: JiraExportConfiguration(
                baseURL: URL(string: "https://acme.atlassian.net")!,
                email: "you@example.com",
                apiToken: "fixture-jira-token",
                projectKey: "FM",
                issueType: "Task"
            )
        )

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.remoteIdentifier, "FM-142")
        XCTAssertEqual(matches.first?.title, "Existing modal close affordance issue")
    }

    func testValidateConfigurationChecksProjectAndIssueType() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)

            if requestCount == 1 {
                XCTAssertEqual(request.url?.absoluteString, "https://acme.atlassian.net/rest/api/3/project/FM")
                let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
                let data = Data(#"{"issueTypes":[{"id":"10001","name":"Task"},{"id":"10002","name":"Bug"}]}"#.utf8)
                return (response, data)
            }

            XCTAssertEqual(request.url?.absoluteString, "https://acme.atlassian.net/rest/api/3/issue/createmeta/FM/issuetypes/10001?startAt=0&maxResults=100")
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"fields":[{"fieldId":"summary","key":"summary","name":"Summary","required":true},{"fieldId":"description","key":"description","name":"Description","required":false}]}"#.utf8)
            return (response, data)
        }

        try await provider.validate(
            configuration: JiraExportConfiguration(
                baseURL: URL(string: "https://acme.atlassian.net")!,
                email: "you@example.com",
                apiToken: "fixture-jira-token",
                projectKey: "FM",
                issueType: "Task"
            )
        )
    }

    func testFetchProjectsLoadsAccessibleProjects() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://acme.atlassian.net/rest/api/3/project/search?startAt=0&maxResults=50")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(
                #"{"values":[{"id":"10002","key":"UCAP","name":"Unified Claims Access Portal"},{"id":"10001","key":"OPS","name":"Operations Support"}],"maxResults":50,"total":2}"#.utf8
            )
            return (response, data)
        }

        let projects = try await provider.fetchProjects(
            configuration: JiraConnectionConfiguration(
                baseURL: URL(string: "https://acme.atlassian.net")!,
                email: "you@example.com",
                apiToken: "fixture-jira-token"
            )
        )

        XCTAssertEqual(
            projects,
            [
                JiraProjectOption(projectID: "10001", key: "OPS", name: "Operations Support"),
                JiraProjectOption(projectID: "10002", key: "UCAP", name: "Unified Claims Access Portal")
            ]
        )
    }

    func testFetchProjectsStopsWhenPaginationDoesNotAdvance() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(
                #"{"values":[{"id":"10002","key":"UCAP","name":"Unified Claims Access Portal"}],"maxResults":0,"total":50}"#.utf8
            )
            return (response, data)
        }

        let projects = try await provider.fetchProjects(
            configuration: JiraConnectionConfiguration(
                baseURL: URL(string: "https://acme.atlassian.net")!,
                email: "you@example.com",
                apiToken: "fixture-jira-token"
            )
        )

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(
            projects,
            [JiraProjectOption(projectID: "10002", key: "UCAP", name: "Unified Claims Access Portal")]
        )
    }

    func testFetchIssueTypesLoadsIssueTypesForSelectedProject() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://acme.atlassian.net/rest/api/3/project/UCAP")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"issueTypes":[{"id":"10001","name":"Task"},{"id":"10002","name":"Bug"},{"id":"10003","name":"Task"}]}"#.utf8)
            return (response, data)
        }

        let issueTypes = try await provider.fetchIssueTypes(
            for: "UCAP",
            configuration: JiraConnectionConfiguration(
                baseURL: URL(string: "https://acme.atlassian.net")!,
                email: "you@example.com",
                apiToken: "fixture-jira-token"
            )
        )

        XCTAssertEqual(
            issueTypes,
            [
                JiraIssueTypeOption(id: "10001", name: "Task"),
                JiraIssueTypeOption(id: "10002", name: "Bug")
            ]
        )
    }

    func testFetchIssueTypesUsesProjectIDWhenAvailable() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://acme.atlassian.net/rest/api/3/issuetype/project?projectId=10002")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"[{"id":"10001","name":"Task"},{"id":"10002","name":"Bug"}]"#.utf8)
            return (response, data)
        }

        let issueTypes = try await provider.fetchIssueTypes(
            for: "UCAP",
            projectID: "10002",
            configuration: JiraConnectionConfiguration(
                baseURL: URL(string: "https://acme.atlassian.net")!,
                email: "you@example.com",
                apiToken: "fixture-jira-token"
            )
        )

        XCTAssertEqual(
            issueTypes,
            [
                JiraIssueTypeOption(id: "10001", name: "Task"),
                JiraIssueTypeOption(id: "10002", name: "Bug")
            ]
        )
    }

    func testFetchProjectsSkipsMalformedProjectRowsInsteadOfFailingDecode() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://acme.atlassian.net/rest/api/3/project/search?startAt=0&maxResults=50")
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(
                #"{"values":[{"id":"10002","key":"UCAP"},{"id":"10003","name":"Missing key"},{"id":"10001","key":"OPS","name":"Operations Support"}],"maxResults":50}"#.utf8
            )
            return (response, data)
        }

        let projects = try await provider.fetchProjects(
            configuration: JiraConnectionConfiguration(
                baseURL: URL(string: "https://acme.atlassian.net")!,
                email: "you@example.com",
                apiToken: "fixture-jira-token"
            )
        )

        XCTAssertEqual(
            projects,
            [
                JiraProjectOption(projectID: "10001", key: "OPS", name: "Operations Support"),
                JiraProjectOption(projectID: "10002", key: "UCAP", name: "UCAP")
            ]
        )
    }

    func testValidateConfigurationRejectsUnsupportedRequiredFields() async throws {
        let provider = JiraExportProvider(session: makeMockURLSession())
        var requestCount = 0

        MockURLProtocol.requestHandler = { request in
            requestCount += 1

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            if requestCount == 1 {
                let data = Data(#"{"issueTypes":[{"id":"10001","name":"Task"}]}"#.utf8)
                return (response, data)
            }

            let data = Data(#"{"fields":[{"fieldId":"summary","key":"summary","name":"Summary","required":true},{"fieldId":"customfield_10010","key":"customfield_10010","name":"Customer Impact","required":true}]}"#.utf8)
            return (response, data)
        }

        do {
            try await provider.validate(
                configuration: JiraExportConfiguration(
                    baseURL: URL(string: "https://acme.atlassian.net")!,
                    email: "you@example.com",
                    apiToken: "fixture-jira-token",
                    projectKey: "FM",
                    issueType: "Task"
                )
            )
            XCTFail("Expected Jira validation to fail.")
        } catch let error as AppError {
            guard case .exportFailure(let message) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertTrue(message.contains("Customer Impact"))
        }
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

private func makeScreenshotFileURL(named fileName: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    let pngData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg=="
    )!
    try? pngData.write(to: url)
    return url
}
