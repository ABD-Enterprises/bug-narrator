import Foundation
import XCTest
@testable import BugNarrator

final class TranscriptSessionSchemaTests: XCTestCase {
    func testEncodesAndRoundTripsSchemaVersion() throws {
        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1),
            transcript: "hello",
            duration: 3,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil
        )
        XCTAssertEqual(session.schemaVersion, TranscriptSession.currentSchemaVersion)

        let data = try JSONEncoder().encode(session)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, TranscriptSession.currentSchemaVersion)

        let decoded = try JSONDecoder().decode(TranscriptSession.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, TranscriptSession.currentSchemaVersion)
        XCTAssertEqual(decoded, session)
    }

    func testLegacyJSONWithoutSchemaVersionDecodesAsLegacyVersion() throws {
        // A session file written before the schemaVersion field existed.
        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "createdAt": 0,
          "updatedAt": 0,
          "transcript": "legacy session",
          "duration": 2,
          "model": "whisper-1",
          "markers": [],
          "screenshots": [],
          "sections": [],
          "transcriptQualityFindings": []
        }
        """

        let decoded = try JSONDecoder().decode(TranscriptSession.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.schemaVersion, TranscriptSession.legacySchemaVersion)
        XCTAssertEqual(decoded.transcript, "legacy session")
    }
}
