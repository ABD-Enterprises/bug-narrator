import XCTest
@testable import BugNarrator

/// The transcript budget decides what the extraction request may carry (#1105).
/// Character arithmetic is easy to get off-by-one, and the omitted count is
/// what the user sees, so both are pinned here.
final class IssueExtractionRequestBudgetTests: XCTestCase {

    private let budget = IssueExtractionRequestBudget.maximumTranscriptCharacters

    // MARK: - no sections: the raw transcript is budgeted

    func testShortTranscriptWithoutSectionsPassesThroughTrimmed() {
        let session = makeSession(transcript: "  hello world \n")

        XCTAssertEqual(IssueExtractionRequestBudget.transcriptLines(for: session), ["hello world"])
    }

    func testEmptyTranscriptYieldsNoLinesAndNoBudgetNote() {
        XCTAssertEqual(IssueExtractionRequestBudget.transcriptLines(for: makeSession(transcript: "   ")), [])
    }

    func testTranscriptExactlyAtBudgetIsNotTruncated() {
        let text = String(repeating: "x", count: budget)
        let lines = IssueExtractionRequestBudget.transcriptLines(for: makeSession(transcript: text))

        XCTAssertEqual(lines, [text])
    }

    func testTranscriptOneOverBudgetIsCutAndTheNoteCountsOneOmittedCharacter() {
        let text = String(repeating: "x", count: budget + 1)
        let lines = IssueExtractionRequestBudget.transcriptLines(for: makeSession(transcript: text))

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].count, budget)
        XCTAssertEqual(lines[1], "[Budget note: omitted 1 transcript character(s) from the extraction request. Export or inspect the full transcript locally if needed.]")
    }

    func testTruncationCountsCharactersNotBytes() {
        // Multi-byte scalars must not shift the cut point or the omitted count.
        let text = String(repeating: "é", count: budget + 3)
        let lines = IssueExtractionRequestBudget.transcriptLines(for: makeSession(transcript: text))

        XCTAssertEqual(lines[0].count, budget)
        XCTAssertTrue(lines[1].contains("omitted 3 transcript character(s)"))
    }

    // MARK: - sections

    func testSectionsEmitHeaderTextAndBlankLine() {
        let section = TranscriptSection(title: "Login", startTime: 0, endTime: 65, text: " The button is dead. ", markerID: nil, screenshotIDs: [])
        let session = makeSession(transcript: "ignored when sections exist", sections: [section])

        XCTAssertEqual(
            IssueExtractionRequestBudget.transcriptLines(for: session),
            ["## Login [\(section.timeRangeLabel)]", "The button is dead.", ""]
        )
    }

    func testScreenshotLineListsOnlyResolvableIDs() {
        let known = SessionScreenshot(elapsedTime: 3, filePath: "/tmp/shots/login-1.png")
        let second = SessionScreenshot(elapsedTime: 4, filePath: "/tmp/shots/login-2.png")
        let unknown = UUID()
        let section = TranscriptSection(title: "Login", startTime: 0, endTime: 10, text: "t", markerID: nil, screenshotIDs: [unknown, known.id, second.id])
        let session = makeSession(transcript: "", screenshots: [known, second], sections: [section])

        let lines = IssueExtractionRequestBudget.transcriptLines(for: session)

        XCTAssertEqual(lines[1], "Screenshots: login-1.png, login-2.png")
    }

    func testScreenshotLineIsOmittedWhenNoIDResolves() {
        let section = TranscriptSection(title: "Login", startTime: 0, endTime: 10, text: "t", markerID: nil, screenshotIDs: [UUID()])
        let lines = IssueExtractionRequestBudget.transcriptLines(for: makeSession(transcript: "", sections: [section]))

        XCTAssertFalse(lines.contains { $0.hasPrefix("Screenshots:") })
    }

    func testBudgetSpansSectionsAndLaterSectionsCountAsOmittedWholesale() {
        // Section 1 uses all but 5 characters; section 2 is cut to 5 and the
        // rest counted; section 3 never starts and is counted in full — without
        // its header, since there is nothing left to put under it.
        let first = TranscriptSection(title: "A", startTime: 0, endTime: 1, text: String(repeating: "a", count: budget - 5), markerID: nil, screenshotIDs: [])
        let second = TranscriptSection(title: "B", startTime: 1, endTime: 2, text: String(repeating: "b", count: 12), markerID: nil, screenshotIDs: [])
        let third = TranscriptSection(title: "C", startTime: 2, endTime: 3, text: String(repeating: "c", count: 30), markerID: nil, screenshotIDs: [])
        let session = makeSession(transcript: "", sections: [first, second, third])

        let lines = IssueExtractionRequestBudget.transcriptLines(for: session)

        XCTAssertTrue(lines.contains("## B [\(second.timeRangeLabel)]"))
        XCTAssertTrue(lines.contains("bbbbb"))
        XCTAssertFalse(lines.contains("## C [\(third.timeRangeLabel)]"))
        XCTAssertEqual(lines.last, "[Budget note: omitted \(7 + 30) transcript character(s) from the extraction request. Export or inspect the full transcript locally if needed.]")
    }

    func testACutWithOneCharacterOfBudgetLeftKeepsThatCharacter() {
        let first = TranscriptSection(title: "A", startTime: 0, endTime: 1, text: String(repeating: "a", count: budget - 1), markerID: nil, screenshotIDs: [])
        let second = TranscriptSection(title: "B", startTime: 1, endTime: 2, text: "bbb", markerID: nil, screenshotIDs: [])
        let lines = IssueExtractionRequestBudget.transcriptLines(for: makeSession(transcript: "", sections: [first, second]))

        XCTAssertTrue(lines.contains("b"))
        XCTAssertTrue(lines.last?.contains("omitted 2 transcript character(s)") == true)
    }

    func testHeadersAndScreenshotLinesAreNotChargedToTheBudget() {
        // Documented behaviour: only section text is budgeted. A section whose
        // text exactly fills the budget still gets its header and screenshot line.
        let shot = SessionScreenshot(elapsedTime: 1, filePath: "/tmp/s.png")
        let section = TranscriptSection(title: "Only", startTime: 0, endTime: 1, text: String(repeating: "z", count: budget), markerID: nil, screenshotIDs: [shot.id])
        let lines = IssueExtractionRequestBudget.transcriptLines(for: makeSession(transcript: "", screenshots: [shot], sections: [section]))

        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[2].count, budget)
        XCTAssertFalse(lines.contains { $0.hasPrefix("[Budget note") })
    }

    // MARK: - fileSize

    func testFileSizeReturnsNilForAMissingFileAndBytesForARealOne() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("BugNarrator-missing-\(UUID().uuidString)")
        XCTAssertNil(IssueExtractionRequestBudget.fileSize(for: missing))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BugNarrator-size-\(UUID().uuidString)")
        try Data(count: 1_234).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(IssueExtractionRequestBudget.fileSize(for: url), 1_234)
    }

    // MARK: - Helpers

    private func makeSession(transcript: String, screenshots: [SessionScreenshot] = [], sections: [TranscriptSection] = []) -> TranscriptSession {
        TranscriptSession(
            createdAt: Date(),
            transcript: transcript,
            duration: 10,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            screenshots: screenshots,
            sections: sections
        )
    }
}
