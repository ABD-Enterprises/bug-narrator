import Foundation
import XCTest
@testable import BugNarrator

final class OperationalTelemetryRecorderTests: XCTestCase {
    func testRecorderAppendsJSONLEvents() throws {
        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-OperationalTelemetryRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("telemetry.jsonl")
        let recorder = OperationalTelemetryRecorder(storageURL: storageURL)

        recorder.record("recording_started", metadata: ["has_openai_key": "yes"])
        recorder.record("transcription_completed", metadata: ["model": "whisper-1"])

        let lines = try String(contentsOf: storageURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("recording_started"))
        XCTAssertTrue(lines[1].contains("transcription_completed"))
    }

    func testRecorderRedactsSensitiveMetadataBeforePersisting() throws {
        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-OperationalTelemetryRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("telemetry.jsonl")
        let recorder = OperationalTelemetryRecorder(storageURL: storageURL)

        recorder.record(
            "token_validation_failed",
            metadata: [
                "githubToken": "github_pat_secret",
                "note": "Bearer github_pat_secret"
            ]
        )

        let event = try XCTUnwrap(recorder.recentEvents(limit: 1).first)
        XCTAssertEqual(event.metadata["githubToken"], "<redacted>")
        XCTAssertEqual(event.metadata["note"], "<redacted>")
        XCTAssertFalse(try String(contentsOf: storageURL, encoding: .utf8).contains("github_pat_secret"))
    }
}
