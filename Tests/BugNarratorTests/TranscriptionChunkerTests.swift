import AVFoundation
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

    // MARK: - size forces re-encoding even under the duration threshold (#1099)

    func testOversizedSourceWithinOneChunkIsPlannedAsASingleSpan() {
        XCTAssertEqual(
            DefaultTranscriptionChunker.plan(totalDuration: 360, maxChunkDuration: max, minimumTailDuration: minTail, sourceExceedsUploadLimit: true),
            [Span(startTime: 0, duration: 360)]
        )
        // Exactly one chunk long is still "within one chunk": one span, not none.
        XCTAssertEqual(
            DefaultTranscriptionChunker.plan(totalDuration: 480, maxChunkDuration: max, minimumTailDuration: minTail, sourceExceedsUploadLimit: true),
            [Span(startTime: 0, duration: 480)]
        )
    }

    func testSizeFlagDoesNotChangeDurationDrivenBoundaries() {
        // Over the duration threshold the plan is identical either way: the
        // size flag only decides whether a within-one-chunk source is exported.
        let withFlag = DefaultTranscriptionChunker.plan(totalDuration: 1000, maxChunkDuration: max, minimumTailDuration: minTail, sourceExceedsUploadLimit: true)
        XCTAssertEqual(withFlag, plan(1000))
        XCTAssertEqual(withFlag, [Span(startTime: 0, duration: 480), Span(startTime: 480, duration: 480), Span(startTime: 960, duration: 40)])
    }

    func testOversizedSourceWithNoDurationIsNotPlanned() {
        // A zero or unreadable duration must not yield a zero-length export.
        XCTAssertEqual(DefaultTranscriptionChunker.plan(totalDuration: 0, maxChunkDuration: max, minimumTailDuration: minTail, sourceExceedsUploadLimit: true), [])
        XCTAssertEqual(DefaultTranscriptionChunker.plan(totalDuration: .nan, maxChunkDuration: max, minimumTailDuration: minTail, sourceExceedsUploadLimit: true), [])
        XCTAssertEqual(DefaultTranscriptionChunker.plan(totalDuration: 360, maxChunkDuration: 0, minimumTailDuration: minTail, sourceExceedsUploadLimit: true), [])
    }
}

// MARK: - size-driven chunking (#1099)

/// Debug mode records 16-bit 44.1 kHz mono WAV (~5.05 MiB/min). Between ~4.75
/// and 8 minutes such a file is under the duration threshold but over
/// `AudioUploadPolicy.maximumSingleUploadBytes`, so it used to ship whole and be
/// rejected by the upload gate. These tests drive the real chunker with a
/// generated WAV of the offending length: the plan must re-encode it.
final class TranscriptionChunkerSizeTests: XCTestCase {

    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs { try? FileManager.default.removeItem(at: url) }
        temporaryURLs = []
        super.tearDown()
    }

    /// Writes a valid silent PCM WAV (16-bit, 44.1 kHz, mono) of `seconds`.
    private func makeSilentWAV(seconds: Int, name: String) throws -> URL {
        let sampleRate: UInt32 = 44_100
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataSize = UInt32(seconds) * byteRate

        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            header.append(Data(bytes: &little, count: MemoryLayout<T>.size))
        }
        header.append(Data("RIFF".utf8)); append(UInt32(36 + dataSize)); header.append(Data("WAVE".utf8))
        header.append(Data("fmt ".utf8)); append(UInt32(16)); append(UInt16(1))
        append(channels); append(sampleRate); append(byteRate); append(blockAlign); append(bitsPerSample)
        header.append(Data("data".utf8)); append(dataSize)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-\(name)-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        temporaryURLs.append(url)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: Data(count: Int(dataSize)))
        return url
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    func testSixMinuteWAVExceedsTheUploadGateButNotTheDurationThreshold() async throws {
        // The premise of the defect, checked on a real file rather than by arithmetic.
        let wav = try makeSilentWAV(seconds: 6 * 60, name: "six-minute")
        XCTAssertGreaterThan(try fileSize(wav), Int64(AudioUploadPolicy.maximumSingleUploadBytes))
        XCTAssertThrowsError(try AudioUploadPolicy().validate(fileURL: wav))
    }

    func testSixMinuteWAVIsReencodedIntoAnUploadableChunk() async throws {
        let wav = try makeSilentWAV(seconds: 6 * 60, name: "six-minute")
        let chunks = try await DefaultTranscriptionChunker().chunks(for: wav)
        temporaryURLs.append(contentsOf: chunks.filter(\.isTemporary).map(\.fileURL))

        XCTAssertEqual(chunks.count, 1, "6 minutes is under the 8-minute duration threshold: one chunk")
        let chunk = try XCTUnwrap(chunks.first)
        XCTAssertTrue(chunk.isTemporary, "the source is over the upload limit, so it must be re-encoded, not shipped whole")
        XCTAssertNotEqual(chunk.fileURL, wav)
        XCTAssertEqual(chunk.fileURL.pathExtension, "m4a")
        XCTAssertEqual(chunk.startTime, 0)
        // The whole point: the thing we upload now passes the gate.
        XCTAssertNoThrow(try AudioUploadPolicy().validate(fileURL: chunk.fileURL))
    }

    func testWAVUnderTheUploadLimitStillShipsWhole() async throws {
        let wav = try makeSilentWAV(seconds: 60, name: "one-minute")
        XCTAssertLessThanOrEqual(try fileSize(wav), Int64(AudioUploadPolicy.maximumSingleUploadBytes))
        let chunks = try await DefaultTranscriptionChunker().chunks(for: wav)
        XCTAssertEqual(chunks.map(\.fileURL), [wav])
        XCTAssertEqual(chunks.map(\.isTemporary), [false])
    }

    /// The pre-existing contract: an m4a under 8 minutes is uploaded as-is.
    func testM4AUnderEightMinutesShipsWholeAndUntouched() async throws {
        let m4a = try makeSilentM4A(seconds: 30, name: "half-minute")
        let bytesBefore = try Data(contentsOf: m4a)

        let chunks = try await DefaultTranscriptionChunker().chunks(for: m4a)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.fileURL, m4a)
        XCTAssertEqual(chunks.first?.isTemporary, false)
        XCTAssertEqual(chunks.first?.startTime, 0)
        XCTAssertEqual(try Data(contentsOf: m4a), bytesBefore, "the source file must not be rewritten")
    }

    /// Writes a silent AAC m4a of `seconds` via AVAudioFile (44.1 kHz mono).
    private func makeSilentM4A(seconds: Int, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-\(name)-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        temporaryURLs.append(url)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: AudioRecorderCaptureFormat.aacM4A.recordingSettings)
        let frames = AVAudioFrameCount(4_096)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        var written: AVAudioFramePosition = 0
        let total = AVAudioFramePosition(seconds) * 44_100
        while written < total {
            try file.write(from: buffer)
            written += AVAudioFramePosition(frames)
        }
        return url
    }
}
