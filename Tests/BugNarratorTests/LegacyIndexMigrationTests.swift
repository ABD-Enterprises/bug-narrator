import Foundation
import XCTest
@testable import BugNarrator

/// #957 encrypted the session index. Every existing install had a PLAINTEXT
/// index, and the migration claim — "unprotect passes non-prefixed payloads
/// through, so an old index still loads and is rewritten protected" — shipped
/// as a source comment with no test behind it. This is a data-loss path: if it
/// is wrong, a user's whole library reads as empty after updating.
final class LegacyIndexMigrationTests: XCTestCase {
    func testAPlaintextIndexFromBeforeEncryptionStillLoadsAndIsRewrittenProtected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-LegacyIndex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storageURL = root.appendingPathComponent("sessions.json")
        let indexURL = root.appendingPathComponent("sessions.index.json")
        let backupURL = root.appendingPathComponent("sessions.index.backup.json")
        let protector = KeychainSessionDataProtector(keychainService: MockKeychainService())

        // 1. A current-format library.
        let store = TranscriptStore(storageURL: storageURL, sessionDataProtector: protector)
        try store.add(makeSampleTranscriptSession(index: 1))
        XCTAssertEqual(store.libraryEntries.count, 1)

        // 2. Rewind it to the pre-#957 shape: decrypt the index and write it back
        //    in the clear, exactly as an install that never saw #957 would have.
        let encrypted = try Data(contentsOf: indexURL)
        let plaintext = try protector.unprotect(encrypted)
        XCTAssertNotEqual(plaintext, encrypted, "Precondition: the current index really is encrypted.")
        try plaintext.write(to: indexURL)
        try plaintext.write(to: backupURL)

        // 3. The upgrade: a new store opens the legacy library.
        let upgraded = TranscriptStore(storageURL: storageURL, sessionDataProtector: protector)
        XCTAssertEqual(
            upgraded.libraryEntries.count,
            1,
            "A pre-#957 plaintext index must still load. Zero here means every existing user's library reads as empty after updating."
        )

        // 4. And it must be re-protected on the next write, not left in the clear.
        try upgraded.add(makeSampleTranscriptSession(index: 2))
        let rewritten = try Data(contentsOf: indexURL)
        XCTAssertNotEqual(rewritten, try protector.unprotect(rewritten), "The index must be encrypted again after a save.")
        XCTAssertEqual(upgraded.libraryEntries.count, 2)
    }
}
