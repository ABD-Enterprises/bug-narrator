import Foundation
import XCTest
@testable import BugNarrator

/// The bearer token the local transcription server requires (#1270).
///
/// The server refuses every request that does not carry the token, so the app
/// and the server have to agree on one. The token file next to the managed
/// install is where they agree, and the contract fixture keeps the macOS,
/// Windows and Python sides from drifting apart.
final class LocalServerTokenStoreTests: XCTestCase {
    private func makeInstallDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarratorTokenTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testTheTokenIsCreatedOnceAndThenReused() throws {
        let directory = makeInstallDirectory()

        let first = try XCTUnwrap(LocalServerTokenStore.token(installDirectory: directory))

        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: LocalServerTokenStore.tokenFileURL(installDirectory: directory).path))

        // A second call reuses the stored token, so the app and the server that
        // reads the same file agree on it.
        XCTAssertEqual(first, LocalServerTokenStore.token(installDirectory: directory))
        XCTAssertEqual(first, LocalServerTokenStore.storedToken(installDirectory: directory))
    }

    func testTheTokenFileIsReadableByItsOwnerOnly() throws {
        let directory = makeInstallDirectory()
        let token = try XCTUnwrap(LocalServerTokenStore.token(installDirectory: directory))

        let url = LocalServerTokenStore.tokenFileURL(installDirectory: directory)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.int16Value, 0o600)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), token)
    }

    func testAStoredTokenIsReadBackUnchanged() throws {
        let directory = makeInstallDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = LocalServerTokenStore.tokenFileURL(installDirectory: directory)
        try Data("  a-stored-token  ".utf8).write(to: url)

        XCTAssertEqual("a-stored-token", LocalServerTokenStore.storedToken(at: url))
    }

    func testAFreshTokenIsLongAndURLSafe() {
        let token = LocalServerTokenStore.newToken()

        XCTAssertGreaterThanOrEqual(token.count, 32)
        XCTAssertFalse(token.contains("+"))
        XCTAssertFalse(token.contains("/"))
        XCTAssertFalse(token.contains("="))
        XCTAssertNotEqual(token, LocalServerTokenStore.newToken())
    }

    /// The path, the file name and the environment variable are shared with the
    /// Windows port and the Python server through a committed fixture.
    func testTheTokenPathMatchesTheSharedContractFixture() throws {
        let fixturesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // BugNarratorTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("contract-fixtures", isDirectory: true)
        let fixtureURL = fixturesDirectory.appendingPathComponent("local-server-token.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path))

        let fixture = try JSONDecoder().decode(
            LocalServerTokenContract.self,
            from: Data(contentsOf: fixtureURL)
        )

        XCTAssertEqual(LocalServerTokenStore.tokenFileName, fixture.tokenFileName)
        XCTAssertEqual(LocalServerTokenStore.environmentVariable, fixture.environmentVariable)
        XCTAssertEqual(LocalServerTokenStore.authorizationScheme, fixture.authorizationScheme)

        // The macOS directory is relative to the user's home directory, the
        // same convention the Python server and the Windows port use.
        let expected = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(fixture.macos.directoryRelativeToHome, isDirectory: true)
            .appendingPathComponent(fixture.tokenFileName)
        XCTAssertEqual(LocalServerPaths.defaultInstallDirectory.appendingPathComponent(fixture.tokenFileName), expected)
    }
}

private struct LocalServerTokenContract: Decodable {
    struct MacOS: Decodable {
        let directoryRelativeToHome: String
    }

    let tokenFileName: String
    let environmentVariable: String
    let authorizationScheme: String
    let macos: MacOS
}
