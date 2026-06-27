import Foundation
import XCTest
@testable import BugNarrator

final class ExportReceiptStoreTests: XCTestCase {
    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportReceiptStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testAbsentFileReturnsNoReceipts() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ExportReceiptStore(storageURL: dir.appendingPathComponent("export-receipts.json"))

        let receipts = try await store.allReceipts()
        XCTAssertTrue(receipts.isEmpty)
    }

    func testCorruptFileFailsClosedAndPreservesCorruptSnapshot() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storageURL = dir.appendingPathComponent("export-receipts.json")
        try Data("{ this is not valid json".utf8).write(to: storageURL)

        let store = ExportReceiptStore(storageURL: storageURL)

        // Reads fail closed rather than reporting "no receipts" (which would let an
        // already-exported issue be duplicated).
        do {
            _ = try await store.receipt(for: "bnexp-deadbeef")
            XCTFail("Expected the corrupt store to fail closed")
        } catch is AppError {
            // expected
        }

        // The corrupt bytes are preserved for forensics, and the original is untouched.
        let backupURL = dir.appendingPathComponent("export-receipts.corrupt.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertEqual(try Data(contentsOf: backupURL), try Data(contentsOf: storageURL))
    }

    func testValidFileLoadsReceipts() async throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storageURL = dir.appendingPathComponent("export-receipts.json")
        let store = ExportReceiptStore(storageURL: storageURL)

        try await store.markSucceeded(
            fingerprint: "bnexp-1",
            sourceIssueID: UUID(),
            destination: .github,
            targetIdentity: "acme/bugnarrator",
            remoteIdentifier: "#1",
            remoteURL: URL(string: "https://github.com/acme/bugnarrator/issues/1")
        )

        let reloaded = ExportReceiptStore(storageURL: storageURL)
        let receipts = try await reloaded.allReceipts()
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.remoteIdentifier, "#1")
    }
}
