import Foundation
import XCTest
@testable import BugNarrator

/// Probe: can a v1-shaped index (no `entries` key) be recovered at all?
final class V1IndexProbeTests: XCTestCase {
    /// The regression both reviewers caught in the first cut of #1017: making
    /// every key optional let `{}` parse as a valid EMPTY library, which
    /// overwrote the good backup and armed the next save to delete every
    /// session file. A file naming no sessions must still fail loudly.
    func testAnIndexNamingNoSessionsDoesNotWipeTheLibrary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-CorruptIndex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storageURL = root.appendingPathComponent("sessions.json")
        let protector = KeychainSessionDataProtector(keychainService: MockKeychainService())
        let seed = TranscriptStore(storageURL: storageURL, sessionDataProtector: protector)
        let session = makeSampleTranscriptSession(index: 1)
        try seed.add(session)

        let sessionFile = root.appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(session.id.uuidString).appendingPathExtension("json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFile.path), "Precondition: the session file exists.")

        // Corrupt ONLY the primary index. The backup stays valid.
        try Data("{}".utf8).write(to: root.appendingPathComponent("sessions.index.json"))

        let reopened = TranscriptStore(storageURL: storageURL, sessionDataProtector: protector)
        XCTAssertEqual(
            reopened.libraryEntries.count,
            1,
            "A corrupt primary index must fall back to the backup, not load empty."
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sessionFile.path),
            "The session file must survive a corrupt index."
        )
    }

    func testV1IndexWithoutEntriesKeyIsRecovered() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-V1Probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storageURL = root.appendingPathComponent("sessions.json")
        let protector = KeychainSessionDataProtector(keychainService: MockKeychainService())

        // Build a real library so the Sessions/<id>.json files genuinely exist.
        let seed = TranscriptStore(storageURL: storageURL, sessionDataProtector: protector)
        let session = makeSampleTranscriptSession(index: 1)
        try seed.add(session)
        XCTAssertEqual(seed.libraryEntries.count, 1)

        // Rewind the index to the v1 shape: sessionIDs only, no `entries` key.
        let indexURL = root.appendingPathComponent("sessions.index.json")
        let backupURL = root.appendingPathComponent("sessions.index.backup.json")
        let v1 = #"{"version":1,"sessionIDs":["\#(session.id.uuidString)"]}"#
        try Data(v1.utf8).write(to: indexURL)
        try Data(v1.utf8).write(to: backupURL)

        let reopened = TranscriptStore(storageURL: storageURL, sessionDataProtector: protector)
        XCTAssertEqual(
            reopened.libraryEntries.count,
            1,
            "A v1 index names its sessions in sessionIDs and the session files are intact on disk, so the library must be recoverable."
        )
    }
}
