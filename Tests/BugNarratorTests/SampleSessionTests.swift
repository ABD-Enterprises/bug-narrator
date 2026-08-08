import XCTest
@testable import BugNarrator

/// #374 (re-scoped text-only): a bundled demo session so a new user can see
/// what BugNarrator produces without spending provider credit or downloading a
/// local model.
final class SampleSessionTests: XCTestCase {
    func testSampleIsDeterministic() {
        let a = SampleSession.make()
        let b = SampleSession.make()

        XCTAssertEqual(a, b, "The sample must be a fixture, not something that varies per call.")
        XCTAssertEqual(a.id, SampleSession.id, "A stable id lets the sample be found and removed without matching on title.")
    }

    func testSampleIsTaggedAndNeverPassesAsUserData() {
        let sample = SampleSession.make()

        XCTAssertTrue(sample.isSampleSession)
        XCTAssertTrue(
            sample.metadataSummary.hasPrefix("Sample"),
            "The library row must say so; a demo that reads like the user's own recording is worse than no demo."
        )
    }

    func testRealSessionsAreNotMarkedAsSamples() {
        let real = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            transcript: "a real session",
            duration: 10,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil
        )

        XCTAssertFalse(real.isSampleSession, "isSampleSession must default to false.")
        XCTAssertFalse(real.metadataSummary.hasPrefix("Sample"))
    }

    func testSampleCarriesTheFullPipelineOutput() {
        let sample = SampleSession.make()

        XCTAssertFalse(sample.transcript.isEmpty, "Expected a transcript.")
        XCTAssertFalse(sample.markers.isEmpty, "Expected timeline markers.")

        let extraction = try? XCTUnwrap(sample.issueExtraction)
        XCTAssertNotNil(extraction, "The point of the demo is the extracted output.")
        XCTAssertFalse(extraction?.summary.isEmpty ?? true, "Expected a review summary.")

        let issues = sample.issueExtraction?.issues ?? []
        XCTAssertGreaterThanOrEqual(issues.count, 2, "Expected more than one issue.")
        XCTAssertGreaterThan(
            Set(issues.map(\.category)).count, 1,
            "Spanning more than one category is what shows the extraction is doing real classification."
        )
    }

    func testSampleNeedsNoProviderOrAudio() {
        let sample = SampleSession.make()

        XCTAssertTrue(sample.screenshots.isEmpty, "Text-only per the re-scope — no bundled image asset.")
        XCTAssertNil(sample.pendingTranscription, "Nothing is queued for transcription; the content is canned.")
        XCTAssertEqual(sample.model, "sample", "Must not claim to have been produced by a real provider model.")
    }

    /// Sessions written before `isSampleSession` existed must still load.
    func testDecodingASessionWithoutTheFieldDefaultsToFalse() throws {
        let sample = SampleSession.make()
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder.bugNarratorTestEncoder.encode(sample)
        ) as? [String: Any] ?? [:]

        XCTAssertNotNil(json["isSampleSession"], "Precondition: the field is encoded.")
        json.removeValue(forKey: "isSampleSession")

        let legacy = try JSONDecoder.bugNarratorTestDecoder.decode(
            TranscriptSession.self,
            from: JSONSerialization.data(withJSONObject: json)
        )

        XCTAssertFalse(legacy.isSampleSession, "A pre-existing session must decode, not throw, and default to false.")
        XCTAssertEqual(legacy.id, sample.id, "The rest of the session must survive the round trip.")
    }
}

private extension JSONEncoder {
    static var bugNarratorTestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var bugNarratorTestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
