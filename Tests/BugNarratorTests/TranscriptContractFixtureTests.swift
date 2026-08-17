import Foundation
import XCTest
@testable import BugNarrator

/// The shared macOS/Windows `transcript.md` contract (#1000).
///
/// Before this, each platform asserted parity against its own retyped literal,
/// so both suites could be green while disagreeing — the mechanism behind the
/// drift #965 catalogued. Windows' `MatchesMacTranscriptContract` pinned
/// "Mar 17, 2026 at 3:00:00 PM" for an instant macOS renders as
/// "Mar 17, 2026 at 11:00:00 AM" in America/New_York.
///
/// Both implementations now render the SAME committed input and must produce
/// the SAME committed output, under `SessionTimestampOptions.invariant`.
final class TranscriptContractFixtureTests: XCTestCase {
    private var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // BugNarratorTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("contract-fixtures", isDirectory: true)
    }

    /// The canonical session. Kept in code AND serialized to the fixture
    /// directory so Windows can build the same input without reading Swift.
    private func canonicalSession() -> TranscriptSession {
        let created = Date(timeIntervalSince1970: 1_773_759_600) // 2026-03-17T15:00:00Z
        let marker = SessionMarker(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            index: 1,
            elapsedTime: 30,
            createdAt: created.addingTimeInterval(30),
            title: "Checkout button clipped",
            note: "Right edge is cut off at 1280 wide.",
            screenshotID: nil
        )
        return TranscriptSession(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            createdAt: created,
            transcript: "The checkout button is clipped on the right at 1280 wide.",
            duration: 120,
            model: "whisper-1",
            languageHint: "en",
            prompt: nil,
            markers: [marker]
        )
    }

    /// Regenerates the golden from the real renderer and diffs it. A change to
    /// `markdownContent` that the fixture does not expect fails here, which is
    /// the whole point — the fixture is a contract, not a snapshot to rubber-stamp.
    func testTranscriptMarkdownMatchesTheCommittedGolden() throws {
        let produced = canonicalSession().markdownContent(timestampOptions: .invariant)
        let goldenURL = fixturesDirectory.appendingPathComponent("transcript.golden.md")

        if ProcessInfo.processInfo.environment["BUGNARRATOR_UPDATE_CONTRACT_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(
                at: fixturesDirectory,
                withIntermediateDirectories: true
            )
            try produced.write(to: goldenURL, atomically: true, encoding: .utf8)
            return
        }

        guard let golden = try? String(contentsOf: goldenURL, encoding: .utf8) else {
            return XCTFail(
                "Missing \(goldenURL.path). Regenerate with BUGNARRATOR_UPDATE_CONTRACT_FIXTURES=1."
            )
        }

        XCTAssertEqual(
            produced,
            golden,
            "transcript.md drifted from the committed contract. If the change is intended, "
                + "regenerate with BUGNARRATOR_UPDATE_CONTRACT_FIXTURES=1 and expect the Windows suite to fail until it is updated too."
        )
    }

    /// The pinned rendering is the point of the whole exercise: without it the
    /// golden would differ per machine and could never bind two platforms.
    func testInvariantTimestampIsMachineIndependentAndASCII() {
        let rendered = canonicalSession().markdownContent(timestampOptions: .invariant)

        XCTAssertTrue(
            rendered.contains("- Recorded: Mar 17, 2026 at 3:00:00 PM"),
            "Invariant rendering must be UTC and ASCII — the exact line Windows pins."
        )
        XCTAssertFalse(
            rendered.unicodeScalars.contains { $0.value == 0x202F || $0.value == 0x00A0 },
            "No U+202F/U+00A0 may survive into the contract. Apple's formatter emits U+202F "
                + "before AM/PM and .NET emits ASCII, so an unnormalized fixture would be "
                + "byte-unmatchable while looking identical."
        )
    }

    /// Shipped behavior must not move. The default stays locale/timezone-local,
    /// which is what a user reading their own export expects.
    func testDefaultRenderingIsUnchangedAndLocal() {
        let session = canonicalSession()

        XCTAssertEqual(
            session.markdownContent,
            session.markdownContent(timestampOptions: .current),
            "The bare property must remain exactly today's behavior."
        )

        if TimeZone.current.secondsFromGMT(for: session.createdAt) != 0 {
            XCTAssertNotEqual(
                session.markdownContent,
                session.markdownContent(timestampOptions: .invariant),
                "Outside UTC the local rendering must differ — that difference is the bug Windows could not see."
            )
        }
    }
}
