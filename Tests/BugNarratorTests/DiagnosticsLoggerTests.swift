import XCTest
@testable import BugNarrator

final class DiagnosticsLoggerTests: XCTestCase {
    func testDefaultDiagnosticsStoreUsesTemporaryPathDuringUnitTests() {
        let storageURL = DiagnosticsLogStore.defaultStorageURL(fileManager: .default)

        XCTAssertTrue(storageURL.path.contains(FileManager.default.temporaryDirectory.path))
        XCTAssertTrue(storageURL.lastPathComponent.hasPrefix("recent-log-"))
    }

    func testFreeformRedactionSanitizesKnownTokenPatterns() {
        let sanitized = DiagnosticsRedactor.sanitizeFreeformText(
            """
            OpenAI sk-test_TOKEN-123 GitHub github_pat_testTOKEN123 cli ghp_TESTTOKEN123 header Bearer test.token-123
            """
        )

        XCTAssertTrue(sanitized.contains("<redacted>"))
        XCTAssertFalse(sanitized.contains("sk-test_TOKEN-123"))
        XCTAssertFalse(sanitized.contains("github_pat_testTOKEN123"))
        XCTAssertFalse(sanitized.contains("ghp_TESTTOKEN123"))
        XCTAssertFalse(sanitized.contains("Bearer test.token-123"))
    }

    func testLoggerRedactsCredentialsFromMetadataAndMessage() async {
        BugNarratorDiagnostics.setDebugModeEnabled(true)
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsLoggerTests-\(UUID().uuidString)")
            .appendingPathExtension("json")
        let store = DiagnosticsLogStore(storageURL: storageURL)
        let logger = DiagnosticsLogger(category: .settings, store: store)

        logger.info(
            .validateAIProviderSucceeded,
            "Validation failed for fixture-openai-key and Bearer fixture-github-pat",
            metadata: [
                "apiKey": "fixture-openai-key",
                "githubToken": "fixture-github-pat",
                "note": "Bearer fixture-github-pat"
            ]
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        let entry = await store.recentEntries().first
        XCTAssertEqual(entry?.metadata["apiKey"], "<redacted>")
        XCTAssertEqual(entry?.metadata["githubToken"], "<redacted>")
        XCTAssertEqual(entry?.metadata["note"], "<redacted>")
        XCTAssertEqual(entry?.event, DiagnosticsEvent.validateAIProviderSucceeded.rawValue)
        XCTAssertFalse(entry?.message.contains("fixture-openai-key") ?? true)
        XCTAssertFalse(entry?.message.contains("fixture-github-pat") ?? true)

        await store.clear()
        BugNarratorDiagnostics.setDebugModeEnabled(false)
    }

    func testDebugLogsAreSuppressedUnlessDebugModeIsEnabled() async {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsLoggerTests-\(UUID().uuidString)")
            .appendingPathExtension("json")
        let store = DiagnosticsLogStore(storageURL: storageURL)
        let logger = DiagnosticsLogger(category: .settings, store: store)

        BugNarratorDiagnostics.setDebugModeEnabled(false)
        logger.debug(.sessionStartIgnored, "This should not be recorded.")

        try? await Task.sleep(nanoseconds: 50_000_000)
        let suppressedEntries = await store.recentEntries()
        XCTAssertTrue(suppressedEntries.isEmpty)

        BugNarratorDiagnostics.setDebugModeEnabled(true)
        logger.debug(.sessionStartIgnored, "This should be recorded.")

        try? await Task.sleep(nanoseconds: 100_000_000)
        let recordedEntries = await store.recentEntries()
        XCTAssertEqual(recordedEntries.first?.event, DiagnosticsEvent.sessionStartIgnored.rawValue)

        await store.clear()
        BugNarratorDiagnostics.setDebugModeEnabled(false)
    }
}
