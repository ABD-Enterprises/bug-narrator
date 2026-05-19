import XCTest
@testable import BugNarrator

final class DiagnosticsLoggerTests: XCTestCase {
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
