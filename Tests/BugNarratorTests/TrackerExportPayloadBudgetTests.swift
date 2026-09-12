import XCTest
@testable import BugNarrator

final class TrackerExportPayloadBudgetTests: XCTestCase {

    // MARK: - trackerTitle (#1111)

    func testPlainShortTitlePassesThroughUnchanged() {
        XCTAssertEqual(TrackerExportPayloadBudget.trackerTitle("Login button stuck disabled", maxCharacters: 255), "Login button stuck disabled")
    }

    func testWhitespaceRunsAndNewlinesCollapseToSingleSpaces() {
        XCTAssertEqual(
            TrackerExportPayloadBudget.trackerTitle("  Crash\r\non   launch\t\tafter\nupdate  ", maxCharacters: 255),
            "Crash on launch after update"
        )
    }

    func testWhitespaceOnlyTitleBecomesEmpty() {
        XCTAssertEqual(TrackerExportPayloadBudget.trackerTitle(" \n\t ", maxCharacters: 255), "")
        XCTAssertEqual(TrackerExportPayloadBudget.trackerTitle("", maxCharacters: 255), "")
    }

    func testTitleExactlyAtTheCapIsKeptWhole() {
        let title = String(repeating: "a", count: 255)
        XCTAssertEqual(TrackerExportPayloadBudget.trackerTitle(title, maxCharacters: 255), title)
    }

    func testTitleOneOverTheCapIsCutToTheCapEndingInAnEllipsis() {
        let title = String(repeating: "a", count: 256)
        let result = TrackerExportPayloadBudget.trackerTitle(title, maxCharacters: 255)

        XCTAssertEqual(result.count, 255)
        XCTAssertTrue(result.hasSuffix("…"))
        XCTAssertEqual(String(result.dropLast()), String(repeating: "a", count: 254))
    }

    func testCutDoesNotLeaveATrailingSpaceBeforeTheEllipsis() {
        let title = String(repeating: "word ", count: 60) // 300 chars; position 254 is a space
        let result = TrackerExportPayloadBudget.trackerTitle(title, maxCharacters: 255)

        XCTAssertFalse(result.hasSuffix(" …"))
        XCTAssertLessThanOrEqual(result.count, 255)
    }

    func testCollapsingHappensBeforeMeasuring() {
        // 300 characters of text with padding that collapses to 10 must not be cut.
        let padded = "short" + String(repeating: " ", count: 290) + "title"
        XCTAssertEqual(TrackerExportPayloadBudget.trackerTitle(padded, maxCharacters: 255), "short title")
    }

    func testCapCountsCharactersNotBytes() {
        let title = String(repeating: "é", count: 300)
        XCTAssertEqual(TrackerExportPayloadBudget.trackerTitle(title, maxCharacters: 255).count, 255)
    }

    func testHardLimitsMatchTheTrackers() {
        XCTAssertEqual(TrackerExportPayloadBudget.jiraSummaryLimit, 255)
        XCTAssertEqual(TrackerExportPayloadBudget.gitHubTitleLimit, 256)
    }

    // MARK: - truncated(): the existing contract, documented not changed

    func testTruncatedOvershootsMaxCharactersByElevenBySuffixDesign() {
        // Cuts to max - 36 then appends a 47-character suffix, so the result is
        // max + 11. Every caller uses it against a self-imposed body budget with
        // slack, so this is pinned as the current contract, not fixed (#1111).
        let result = TrackerExportPayloadBudget.truncated(String(repeating: "x", count: 1_000), maxCharacters: 500)

        XCTAssertEqual(result.count, 511)
        XCTAssertTrue(result.hasSuffix(" …[truncated by BugNarrator for tracker limits]"))
    }

    func testTruncatedLeavesInBudgetValuesAloneApartFromTrimming() {
        XCTAssertEqual(TrackerExportPayloadBudget.truncated("  fits  ", maxCharacters: 10), "fits")
    }
}
