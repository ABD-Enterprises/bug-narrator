import Foundation
import XCTest
@testable import BugNarrator

final class PrivacyDataExporterTests: XCTestCase {
    func testPrivacyDataExporterWritesManifestAndSessionsWithoutSecrets() throws {
        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-PrivacyDataExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let exporter = PrivacyDataExporter()
        let session = makeSampleTranscriptSession(index: 1)

        let exportURL = try exporter.writeBundle(sessions: [session], to: rootDirectoryURL)
        let manifestData = try Data(contentsOf: exportURL.appendingPathComponent("manifest.json"))
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        let sessionsData = try Data(contentsOf: exportURL.appendingPathComponent("sessions.json"))
        let sessions = try JSONDecoder().decode([TranscriptSession].self, from: sessionsData)

        XCTAssertEqual(manifest?["includesSecrets"] as? Bool, false)
        XCTAssertEqual(manifest?["sessionCount"] as? Int, 1)
        XCTAssertEqual(sessions, [session])
        XCTAssertFalse(String(data: manifestData + sessionsData, encoding: .utf8)?.contains("apiKey") == true)
    }
}
