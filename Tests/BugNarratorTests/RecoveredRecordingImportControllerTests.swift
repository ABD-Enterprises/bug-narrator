import XCTest
@testable import BugNarrator

@MainActor
final class RecoveredRecordingImportControllerTests: XCTestCase {
    func testImportReturnsNoneWhenNoRecordingsAreRecovered() throws {
        let harness = RecoveredRecordingImportControllerHarness(importResult: .success(0))
        defer { harness.cleanup() }

        let outcome = try harness.controller.importRecoveredRecordingsAtLaunch()

        XCTAssertEqual(outcome, .none)
        XCTAssertEqual(harness.controller.recoveredRecordingImportCount, 0)
        XCTAssertEqual(harness.importer.importCallCount, 1)
    }

    func testImportReturnsRecoveredStatusMessageWhenRecordingsAreImported() throws {
        let harness = RecoveredRecordingImportControllerHarness(importResult: .success(2))
        defer { harness.cleanup() }

        let outcome = try harness.controller.importRecoveredRecordingsAtLaunch()

        XCTAssertEqual(harness.controller.recoveredRecordingImportCount, 2)
        XCTAssertEqual(harness.importer.importCallCount, 1)
        XCTAssertEqual(
            outcome,
            .imported(
                message: "Recovered 2 recordings after an unexpected quit. Open Session Library to transcribe them.",
                error: .transcriptionFailure("Recovered recordings are waiting for transcription.")
            )
        )
    }

    func testImportPropagatesImporterFailure() {
        let expectedError = NSError(domain: "RecoveredRecordingImportControllerTests", code: 1)
        let harness = RecoveredRecordingImportControllerHarness(importResult: .failure(expectedError))
        defer { harness.cleanup() }

        XCTAssertThrowsError(try harness.controller.importRecoveredRecordingsAtLaunch()) { error in
            XCTAssertEqual((error as NSError).domain, expectedError.domain)
            XCTAssertEqual((error as NSError).code, expectedError.code)
        }
        XCTAssertEqual(harness.controller.recoveredRecordingImportCount, 0)
        XCTAssertEqual(harness.importer.importCallCount, 1)
    }
}

@MainActor
private final class RecoveredRecordingImportControllerHarness {
    let rootDirectoryURL: URL
    let transcriptStore: TranscriptStore
    let artifactsService: MockArtifactsService
    let importer: MockRecoveredRecordingImporter
    let controller: RecoveredRecordingImportController

    init(importResult: Result<Int, Error>) {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("RecoveredRecordingImportControllerTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        let transcriptStore = TranscriptStore(
            fileManager: fileManager,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json")
        )
        let artifactsService = MockArtifactsService(
            rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts", isDirectory: true)
        )
        let clipboardService = MockClipboardService()
        let sessionLibrary = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: artifactsService,
            clipboardService: clipboardService
        )
        let importer = MockRecoveredRecordingImporter()
        importer.importResult = importResult

        self.rootDirectoryURL = rootDirectoryURL
        self.transcriptStore = transcriptStore
        self.artifactsService = artifactsService
        self.importer = importer
        self.controller = RecoveredRecordingImportController(
            transcriptStore: transcriptStore,
            sessionLibrary: sessionLibrary,
            recoveredRecordingImporter: importer,
            artifactsService: artifactsService
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}
