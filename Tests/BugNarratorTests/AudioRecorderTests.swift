import AVFoundation
import XCTest
@testable import BugNarrator

@MainActor
final class AudioRecorderTests: XCTestCase {
    func testStopRecordingTimesOutWhenRecorderNeverFinalizes() async throws {
        let harness = try AudioRecorderHarness(timeoutNanoseconds: 1_000_000)
        defer { harness.cleanup() }

        try await harness.recorder.startRecording()

        do {
            _ = try await harness.recorder.stopRecording()
            XCTFail("Expected stop recording to time out.")
        } catch {
            XCTAssertEqual(
                error as? AppError,
                .recordingFailure("The recorded audio file did not finish finalizing before the timeout.")
            )
        }
    }

    func testCancelRecordingTimesOutWhenRecorderNeverFinalizes() async throws {
        let harness = try AudioRecorderHarness(timeoutNanoseconds: 1_000_000)
        defer { harness.cleanup() }

        try await harness.recorder.startRecording()
        await harness.recorder.cancelRecording(preserveFile: true)

        XCTAssertEqual(harness.recordingEngine?.stopCallCount, 1)
    }

    func testStopRecordingRejectsCorruptFinalizedAudio() async throws {
        let harness = try AudioRecorderHarness(timeoutNanoseconds: 500_000_000)
        defer { harness.cleanup() }

        try await harness.recorder.startRecording()
        let stopTask = Task {
            try await harness.recorder.stopRecording()
        }

        await waitUntil {
            harness.recordingEngine?.stopCallCount == 1
        }

        let fileURL = try XCTUnwrap(harness.recordingFileURL)
        try Data("not playable audio".utf8).write(to: fileURL)
        let callbackRecorder = try AVAudioRecorder(url: fileURL, settings: harness.callbackRecorderSettings)
        harness.recorder.audioRecorderDidFinishRecording(callbackRecorder, successfully: true)

        do {
            _ = try await stopTask.value
            XCTFail("Expected corrupt audio validation to fail.")
        } catch {
            XCTAssertEqual(error as? AppError, .recordingFailure("The recorded audio file could not be read."))
        }
    }

    func testStartRecordingRemovesPreparedFileWhenRecorderRejectsStart() async throws {
        let harness = try AudioRecorderHarness(timeoutNanoseconds: 500_000_000)
        defer { harness.cleanup() }
        harness.recorderFactory.nextEngineRecordResult = false
        harness.recorderFactory.writePlaceholderFileForNextEngine = true

        do {
            try await harness.recorder.startRecording()
            XCTFail("Expected start recording to fail.")
        } catch {
            XCTAssertEqual(
                error as? AppError,
                .microphoneUnavailable("Check that an input device is connected and available, then try again.")
            )
        }

        let fileURL = try XCTUnwrap(harness.recordingFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}

@MainActor
private final class AudioRecorderHarness {
    let rootDirectoryURL: URL
    let recoveryDirectoryURL: URL
    let recorder: AudioRecorder
    let recorderFactory: AudioRecorderEngineFactorySpy
    let callbackRecorderSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    var recordingEngine: FakeAudioRecorderEngine? {
        recorderFactory.recordingEngine
    }

    var recordingFileURL: URL? {
        recorderFactory.recordingFileURL
    }

    init(timeoutNanoseconds: UInt64) throws {
        rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecorderTests-\(UUID().uuidString)", isDirectory: true)
        recoveryDirectoryURL = rootDirectoryURL.appendingPathComponent("RecoveredRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        let factory = AudioRecorderEngineFactorySpy(recoveryDirectoryURL: recoveryDirectoryURL)
        recorderFactory = factory

        recorder = AudioRecorder(
            permissionAccess: StaticMicrophonePermissionAccess(),
            recoveryDirectoryURL: recoveryDirectoryURL,
            finalizationTimeoutNanoseconds: timeoutNanoseconds
        ) { url, _ in
            factory.makeRecorder(for: url)
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}

@MainActor
private final class AudioRecorderEngineFactorySpy {
    private let recoveryDirectoryURL: URL
    private(set) var engines: [FakeAudioRecorderEngine] = []
    private(set) var recordingFileURL: URL?
    var nextEngineRecordResult = true
    var writePlaceholderFileForNextEngine = false

    var recordingEngine: FakeAudioRecorderEngine? {
        engines.last
    }

    init(recoveryDirectoryURL: URL) {
        self.recoveryDirectoryURL = recoveryDirectoryURL
    }

    func makeRecorder(for url: URL) -> FakeAudioRecorderEngine {
        let isRecordingArtifact = url.standardizedFileURL.path.hasPrefix(recoveryDirectoryURL.standardizedFileURL.path)
        let recordResult = isRecordingArtifact ? nextEngineRecordResult : true

        if isRecordingArtifact, writePlaceholderFileForNextEngine {
            try? Data("partial recorder artifact".utf8).write(to: url)
            writePlaceholderFileForNextEngine = false
        }

        let engine = FakeAudioRecorderEngine(recordResult: recordResult)
        if isRecordingArtifact {
            nextEngineRecordResult = true
        }
        engines.append(engine)

        if isRecordingArtifact {
            recordingFileURL = url
        }

        return engine
    }
}

@MainActor
private final class FakeAudioRecorderEngine: AudioRecorderEngine {
    weak var delegate: (any AVAudioRecorderDelegate)?
    var currentTime: TimeInterval = 3
    private(set) var stopCallCount = 0
    private let recordResult: Bool

    init(recordResult: Bool = true) {
        self.recordResult = recordResult
    }

    func prepareToRecord() -> Bool {
        true
    }

    func record() -> Bool {
        recordResult
    }

    func stop() {
        stopCallCount += 1
    }
}

@MainActor
private final class StaticMicrophonePermissionAccess: MicrophonePermissionAccessing {
    func currentPermissionState() -> MicrophonePermissionState {
        .authorized
    }

    func requestPermissionIfNeeded() async -> MicrophonePermissionState {
        .authorized
    }
}
