import CryptoKit
import XCTest
@testable import BugNarrator

final class LocalTranscriptionManagerTests: XCTestCase {
    @MainActor
    func testReleaseSelectionSkipsAppOnlyReleaseAndRequiresChecksum() throws {
        let image = LocalTranscriptionManager.Asset(name: LocalTranscriptionManager.assetName, size: 135_684_157,
            browser_download_url: URL(string: "https://github.com/ABD-Enterprises/bug-narrator/releases/download/v1/server.dmg")!)
        let checksum = LocalTranscriptionManager.Asset(name: LocalTranscriptionManager.assetName + ".sha256", size: 100,
            browser_download_url: URL(string: "https://github.com/ABD-Enterprises/bug-narrator/releases/download/v1/server.dmg.sha256")!)
        let releases = [
            LocalTranscriptionManager.Release(draft: false, prerelease: false, assets: []),
            LocalTranscriptionManager.Release(draft: true, prerelease: false, assets: [image, checksum]),
            LocalTranscriptionManager.Release(draft: false, prerelease: false, assets: [image]),
            LocalTranscriptionManager.Release(draft: false, prerelease: false, assets: [image, checksum])
        ]
        XCTAssertEqual(LocalTranscriptionManager.selectPackage(from: releases)?.image, image)
        XCTAssertNil(LocalTranscriptionManager.selectPackage(from: Array(releases.prefix(3))))
    }

    @MainActor
    func testAssetURLMustBelongToTheRepository() {
        for address in ["http://github.com/ABD-Enterprises/bug-narrator/releases/download/v1/a",
                        "https://example.com/ABD-Enterprises/bug-narrator/releases/download/v1/a",
                        "https://github.com/other/project/releases/download/v1/a",
                        "https://user@github.com/ABD-Enterprises/bug-narrator/releases/download/v1/a"] {
            XCTAssertFalse(LocalTranscriptionManager.trustedAssetURL(URL(string: address)!))
        }
    }

    func testChecksumRejectsTamperingAndWrongSize() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data("test server".utf8)
        try data.write(to: file)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let manifest = Data("\(hash)  server.dmg\n".utf8)
        XCTAssertNoThrow(try LocalTranscriptionManager.verifyChecksum(file: file, manifest: manifest, expectedSize: Int64(data.count)))
        XCTAssertThrowsError(try LocalTranscriptionManager.verifyChecksum(file: file, manifest: manifest, expectedSize: 1))
        XCTAssertThrowsError(try LocalTranscriptionManager.verifyChecksum(file: file, manifest: Data("not a hash".utf8), expectedSize: Int64(data.count)))
        try Data("bad! server".utf8).write(to: file)
        XCTAssertThrowsError(try LocalTranscriptionManager.verifyChecksum(file: file, manifest: manifest, expectedSize: Int64(data.count)))
    }

    @MainActor
    func testRemovalOnlyDeletesManagedDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed")
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        let unrelated = root.appendingPathComponent("unrelated")
        try Data("keep".utf8).write(to: unrelated)
        try Data("fixture".utf8).write(to: managed.appendingPathComponent("bugnarrator-transcription"))
        let manager = LocalTranscriptionManager(directory: managed)
        XCTAssertTrue(manager.installed)
        manager.remove()
        XCTAssertFalse(manager.installed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
