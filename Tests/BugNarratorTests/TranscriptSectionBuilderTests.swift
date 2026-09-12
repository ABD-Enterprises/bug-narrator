import XCTest
@testable import BugNarrator

/// Section splitting is pure and was only covered by a count assertion in
/// TranscriptionSessionBuilderTests (#1107). Every branch that decides which
/// text lands under which marker is pinned here.
final class TranscriptSectionBuilderTests: XCTestCase {

    // 100 characters, ten distinct decades, so a slice's origin is readable.
    private let transcript = (0..<10).map { String(repeating: "\($0)", count: 10) }.joined()

    private func marker(_ index: Int, at time: TimeInterval, title: String? = nil, screenshotID: UUID? = nil) -> SessionMarker {
        SessionMarker(index: index, elapsedTime: time, title: title ?? "M\(index)", screenshotID: screenshotID)
    }

    private func build(segments: [TranscriptionSegment] = [], markers: [SessionMarker], duration: TimeInterval = 100, transcript: String? = nil) -> [TranscriptSection] {
        TranscriptSectionBuilder.buildSections(transcript: transcript ?? self.transcript, segments: segments, markers: markers, duration: duration)
    }

    // MARK: - degenerate inputs

    func testBlankTranscriptYieldsNoSections() {
        XCTAssertEqual(build(markers: [marker(1, at: 10)], transcript: " \n ").count, 0)
    }

    func testNoMarkersYieldsOneFullSessionSection() {
        let sections = build(markers: [])

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Full Session")
        XCTAssertEqual(sections[0].startTime, 0)
        XCTAssertEqual(sections[0].endTime, 100)
        XCTAssertEqual(sections[0].text, transcript)
        XCTAssertNil(sections[0].markerID)
    }

    // MARK: - intervals

    func testOpeningNotesAppearOnlyWhenTheFirstMarkerIsAfterZero() {
        XCTAssertEqual(build(markers: [marker(1, at: 30)]).map(\.title), ["Opening Notes", "M1"])
        XCTAssertEqual(build(markers: [marker(1, at: 0)]).map(\.title), ["M1"])
    }

    func testIntervalsRunMarkerToNextMarkerAndLastToDuration() {
        let sections = build(markers: [marker(1, at: 20), marker(2, at: 70)])

        XCTAssertEqual(sections.map { [$0.startTime, $0.endTime] }, [[0, 20], [20, 70], [70, 100]])
    }

    func testMarkerLinksAndScreenshotsAreCarriedOntoTheirSection() {
        let shot = UUID()
        let m = marker(1, at: 40, screenshotID: shot)
        let sections = build(markers: [m])

        XCTAssertNil(sections[0].markerID)
        XCTAssertEqual(sections[0].screenshotIDs, [])
        XCTAssertEqual(sections[1].markerID, m.id)
        XCTAssertEqual(sections[1].screenshotIDs, [shot])
    }

    // MARK: - character-backed slicing (no segments)

    func testCharacterSlicesAreProportionalToTime() {
        let sections = build(markers: [marker(1, at: 20), marker(2, at: 70)])

        XCTAssertEqual(sections[0].text, String(repeating: "0", count: 10) + String(repeating: "1", count: 10))
        XCTAssertEqual(sections[1].text.count, 50)
        XCTAssertTrue(sections[1].text.hasPrefix("2") && sections[1].text.hasSuffix("6"))
        XCTAssertEqual(sections[2].text.count, 30)
        XCTAssertTrue(sections[2].text.hasPrefix("7") && sections[2].text.hasSuffix("9"))
    }

    func testLastSectionTakesTheRemainderRegardlessOfRounding() {
        // 3 markers over 100 chars at thirds: rounding must not drop the tail.
        let sections = build(markers: [marker(1, at: 33.3), marker(2, at: 66.6)])
        let rejoined = sections.map(\.text).joined()

        XCTAssertEqual(rejoined.count, transcript.count)
        XCTAssertEqual(rejoined, transcript)
    }

    func testTwoMarkersPressedTogetherDoNotDuplicateTheTranscript() {
        // Reproduction from the ticket: the 0.2 s section used to carry all 100
        // characters, so the three sections totalled 200.
        let sections = build(markers: [marker(1, at: 50), marker(2, at: 50.2)])

        XCTAssertEqual(sections[1].text, "")
        XCTAssertEqual(sections.map(\.text).joined().count, transcript.count)
    }

    func testZeroDurationKeepsTheTranscriptReadable() {
        // With duration 0 the fractions default to 0 and 1, so the single slice
        // is the whole transcript on its own — no fallback involved.
        let sections = build(markers: [marker(1, at: 0)], duration: 0)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].text, transcript)
    }

    // MARK: - segment-backed assignment

    func testSegmentsAreAssignedByMidpointWithHalfOpenIntervals() {
        let segments = [
            TranscriptionSegment(start: 0, end: 10, text: "opening"),      // mid 5  → Opening
            TranscriptionSegment(start: 15, end: 25, text: "boundary"),    // mid 20 → M1 (>= start), not Opening (< end)
            TranscriptionSegment(start: 60, end: 80, text: "late"),        // mid 70 → M2 (>= start)
            TranscriptionSegment(start: 99, end: 101, text: "tail")        // mid 100 → M2: the last interval is closed at duration
        ]
        let sections = build(segments: segments, markers: [marker(1, at: 20), marker(2, at: 70)])

        XCTAssertEqual(sections.map(\.text), ["opening", "boundary", "late tail"])
    }

    func testSegmentTextIsJoinedWithSpacesAndTrimmed() {
        let segments = [
            TranscriptionSegment(start: 0, end: 2, text: "  one "),
            TranscriptionSegment(start: 2, end: 4, text: "two  ")
        ]
        XCTAssertEqual(build(segments: segments, markers: [marker(1, at: 0)]).map(\.text), ["one  two"])
    }

    func testSectionWithNoSegmentsFallsBackToItsCharacterSlice() {
        // Segments only in the first half; the marker at 50 gets the character
        // slice for [50, 100], not the whole transcript and not nothing.
        let segments = [TranscriptionSegment(start: 0, end: 40, text: "spoken early")]
        let sections = build(segments: segments, markers: [marker(1, at: 50)])

        XCTAssertEqual(sections[0].text, "spoken early")
        XCTAssertEqual(sections[1].text, String(transcript.suffix(50)))
    }

    func testSegmentModeNearZeroIntervalIsEmptyNotTheWholeTranscript() {
        let segments = [TranscriptionSegment(start: 0, end: 100, text: "everything")] // mid 50 → M1 [50, 50.2)
        let sections = build(segments: segments, markers: [marker(1, at: 50), marker(2, at: 50.2)])

        XCTAssertEqual(sections[1].text, "everything")
        XCTAssertEqual(sections[2].text, String(transcript.suffix(50)), "no segment lands in [50.2, 100]; character fallback")
        XCTAssertEqual(sections[0].text, String(transcript.prefix(50)))
    }
}
