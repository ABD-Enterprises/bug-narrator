import XCTest
@testable import BugNarrator

/// The chunk plan is pure arithmetic, extracted from the AVAsset export loop so
/// its boundaries can be pinned without an audio fixture (#1095). The export
/// path itself still needs a real asset and is exercised by the transcription
/// flow, not here.
final class TranscriptionChunkerTests: XCTestCase {

    private typealias Span = DefaultTranscriptionChunker.Span
    private let max: TimeInterval = 480      // 8 minutes, the shipped default
    private let minTail: TimeInterval = 1

    private func plan(_ total: TimeInterval, max: TimeInterval? = nil, minTail: TimeInterval? = nil) -> [Span] {
        DefaultTranscriptionChunker.plan(
            totalDuration: total,
            maxChunkDuration: max ?? self.max,
            minimumTailDuration: minTail ?? self.minTail
        )
    }

    // MARK: - not chunked at all (empty plan = send the file whole)

    func testShorterThanMaxIsNotChunked() {
        XCTAssertEqual(plan(120), [])
    }

    func testExactlyMaxIsNotChunked() {
        // The guard is strictly greater-than: a recording of exactly one chunk
        // length ships as a single, non-temporary file.
        XCTAssertEqual(plan(480), [])
    }

    func testNonFiniteDurationIsNotChunked() {
        XCTAssertEqual(plan(.infinity), [])
        XCTAssertEqual(plan(.nan), [])
    }

    func testZeroOrNegativeMaxIsNotChunked() {
        // A misconfigured chunker must never loop forever or divide the file
        // into nothing; it falls back to sending the whole file.
        XCTAssertEqual(plan(1000, max: 0), [])
        XCTAssertEqual(plan(1000, max: -5), [])
        // A short total with max 0 is the case the max>0 guard exists for: without
        // it, min(0, 0.5) = 0, the 0.5 s "tail" is under the fold threshold, and the
        // fold pushes the duration back up to 0.5 — sailing past the zero-duration
        // guard and returning a one-span plan for an unconfigured chunker.
        XCTAssertEqual(plan(0.5, max: 0), [])
    }

    // MARK: - chunked

    func testTwoAndAHalfChunks() {
        XCTAssertEqual(plan(1200), [
            Span(startTime: 0, duration: 480),
            Span(startTime: 480, duration: 480),
            Span(startTime: 960, duration: 240),
        ])
    }

    func testExactMultipleHasNoEmptyTail() {
        // 3 x max exactly: three full chunks and nothing after. A naive loop
        // with a <= comparison would append a zero-length fourth.
        XCTAssertEqual(plan(1440), [
            Span(startTime: 0, duration: 480),
            Span(startTime: 480, duration: 480),
            Span(startTime: 960, duration: 480),
        ])
    }

    func testSpansAreContiguousAndCoverTheWholeRecording() {
        for total in [481.0, 500, 959.9, 960, 961, 1200, 5000] {
            let spans = plan(total)
            XCTAssertEqual(spans.first?.startTime, 0, "total=\(total)")
            for (a, b) in zip(spans, spans.dropFirst()) {
                XCTAssertEqual(a.startTime + a.duration, b.startTime, accuracy: 1e-9, "gap/overlap at \(b.startTime), total=\(total)")
            }
            let end = spans.last.map { $0.startTime + $0.duration } ?? 0
            XCTAssertEqual(end, total, accuracy: 1e-9, "total=\(total)")
            XCTAssertTrue(spans.allSatisfy { $0.duration > 0 }, "no empty span, total=\(total)")
        }
    }

    // MARK: - the tail decision (#1095)

    func testSubThresholdTailIsFoldedIntoThePreviousChunk() {
        // 8:00.5 used to yield a 0.5 s second chunk: its own export and its own
        // API call for half a second of audio. It now rides on the first chunk.
        XCTAssertEqual(plan(480.5), [
            Span(startTime: 0, duration: 480.5),
        ])
    }

    func testTailAtThresholdIsItsOwnChunk() {
        // Exactly the minimum is NOT folded — the threshold is "shorter than".
        XCTAssertEqual(plan(481), [
            Span(startTime: 0, duration: 480),
            Span(startTime: 480, duration: 1),
        ])
    }

    func testFoldingOnlyAffectsTheLastChunk() {
        // 2 x max + 0.5: the fold applies to the final slice only; the first
        // chunk stays exactly max.
        XCTAssertEqual(plan(960.5), [
            Span(startTime: 0, duration: 480),
            Span(startTime: 480, duration: 480.5),
        ])
    }

    func testFoldedChunkNeverExceedsMaxPlusThreshold() {
        // The merged last chunk is bounded: max + (threshold - epsilon). This is
        // what keeps a folded chunk inside the provider's size limit.
        for total in stride(from: 480.0, through: 2000, by: 0.25) {
            for span in plan(total) {
                XCTAssertLessThan(span.duration, max + minTail, "total=\(total)")
            }
        }
    }

    func testThresholdOfZeroDisablesFolding() {
        XCTAssertEqual(plan(480.5, minTail: 0), [
            Span(startTime: 0, duration: 480),
            Span(startTime: 480, duration: 0.5),
        ])
    }
}
