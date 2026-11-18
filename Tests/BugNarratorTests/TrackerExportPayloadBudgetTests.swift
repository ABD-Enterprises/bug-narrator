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
        // With max 2 the kept prefix is "a " — the space must go before the ellipsis.
        XCTAssertEqual(TrackerExportPayloadBudget.trackerTitle("a bcd", maxCharacters: 2), "a…")

        // And at the real cap: "w " has period 2, so the last kept index (253,
        // odd) is a space and must be trimmed away.
        let title = String(repeating: "w ", count: 150)
        let result = TrackerExportPayloadBudget.trackerTitle(title, maxCharacters: 255)
        XCTAssertFalse(result.hasSuffix(" …"))
        XCTAssertTrue(result.hasSuffix("w…"))
        XCTAssertEqual(result.count, 254)
    }

    func testCollapsingHappensBeforeMeasuring() {
        // 300 characters of text with padding that collapses to 10 must not be cut.
        let padded = "short" + String(repeating: " ", count: 290) + "title"
        XCTAssertEqual(TrackerExportPayloadBudget.trackerTitle(padded, maxCharacters: 255), "short title")
    }

    func testCapCountsUTF16UnitsNotBytes() {
        let over = String(repeating: "é", count: 300)
        XCTAssertEqual(TrackerExportPayloadBudget.trackerTitle(over, maxCharacters: 255).utf16.count, 255)

        // 200 characters but 400 UTF-8 bytes: a byte-counting cap would cut this.
        let under = String(repeating: "é", count: 200)
        XCTAssertEqual(TrackerExportPayloadBudget.trackerTitle(under, maxCharacters: 255), under)
    }

    func testHardLimitsMatchTheTrackers() {
        XCTAssertEqual(TrackerExportPayloadBudget.jiraSummaryLimit, 255)
        XCTAssertEqual(TrackerExportPayloadBudget.gitHubTitleLimit, 256)
    }

    // MARK: - trackerTitle: the title is untrusted text too

    func testTitleNeutralizesMentionsAndCrossReferences() {
        let result = TrackerExportPayloadBudget.trackerTitle(
            "@security-team rotate #4821 keys GH-99",
            maxCharacters: 255
        )

        XCTAssertFalse(result.contains("@security-team"), "a live mention survived in the title: \(result)")
        XCTAssertFalse(result.contains("#4821"), "a live cross-reference survived in the title: \(result)")
        XCTAssertFalse(result.lowercased().contains("gh-99"), "a live GH- reference survived in the title: \(result)")
        // The text stays visually identical: only zero-width spaces are added.
        XCTAssertEqual(
            result.replacingOccurrences(of: "\u{200B}", with: ""),
            "@security-team rotate #4821 keys GH-99"
        )
    }

    func testNeutralizedTitleStillFitsTheTrackerCap() {
        // The zero-width spaces count towards the limit, so a title that was
        // already at the cap must not grow past it: the tracker rejects a
        // title over 256 (GitHub) or 255 (Jira).
        //
        // The trailing "@" is the last character on purpose: if the
        // neutralization ran after the cap, the zero-width space it adds
        // would push the title over the limit instead of being cut away with
        // it.
        let title = String(repeating: "a", count: 254) + "@"
        let result = TrackerExportPayloadBudget.trackerTitle(title, maxCharacters: 255)

        XCTAssertLessThanOrEqual(result.utf16.count, 255)
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func testTitleCapCountsUTF16UnitsLikeTheTracker() {
        // Jira counts its 255-character limit in UTF-16 code units, so a
        // title dense in astral-plane characters is twice as long there as
        // it is in characters. A Character-based cap would send a title the
        // tracker rejects.
        let title = String(repeating: "😀", count: 200)
        let result = TrackerExportPayloadBudget.trackerTitle(title, maxCharacters: 255)

        XCTAssertLessThanOrEqual(result.utf16.count, 255)
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func testAMentionIsNeutralizedEvenWhenTheNextCharacterExtendsTheCluster() {
        // A literal search matches whole grapheme clusters, so an "@" that is
        // part of a larger cluster - a combining mark or a variation selector
        // - used to survive untouched.
        let result = TrackerExportPayloadBudget.trackerTitle("@\u{0301}teamuser", maxCharacters: 255)

        XCTAssertTrue(result.contains("@\u{200B}"), "the mention was not neutralized: \(result)")
        XCTAssertTrue(result.contains("\u{0301}"), "the combining mark was dropped: \(result)")
    }

    func testALeadingZeroWidthSpaceIsNotTrimmedAway() {
        // The Windows port trims only the end of a cut title, so the macOS
        // cut must not trim the front either, or the two ports send
        // different titles.
        let result = TrackerExportPayloadBudget.trackerTitle(
            "\u{200B}" + String(repeating: "a", count: 300),
            maxCharacters: 255
        )

        XCTAssertTrue(result.hasPrefix("\u{200B}"), "the leading zero-width space was trimmed away: \(result)")
    }

    func testTheCollapseDoesNotTreatAZeroWidthSpaceAsASeparator() {
        // Swift's whitespace set includes the zero-width space and the
        // Windows port's does not, so a title that carries one would
        // collapse differently on the two ports. Both use one shared set now.
        let result = TrackerExportPayloadBudget.trackerTitle("a\u{200B}b", maxCharacters: 255)

        XCTAssertEqual(result, "a\u{200B}b")
    }

    func testCutTrimsTheZeroWidthSpaceANeutralizedMentionLeavesBehind() {
        // macOS trims the zero-width space a neutralized mention leaves behind,
        // and so must Windows: otherwise the two ports send different titles
        // for the same issue.
        let result = TrackerExportPayloadBudget.trackerTitle("a@b c", maxCharacters: 4)

        XCTAssertFalse(result.unicodeScalars.contains("\u{200B}"), "a zero-width space survived the cut: \(result)")
        XCTAssertEqual(result, "a@…")
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
