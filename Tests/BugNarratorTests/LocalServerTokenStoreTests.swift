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

    /// A token file that was already there with wider permissions must not
    /// stay readable by anyone else once the token is replaced. The
    /// replacement keeps the destination's metadata unless it is told
    /// otherwise, so a file that an earlier version left at 0644 would keep
    /// being world-readable.
    func testAReplacedTokenFileIsOnlyReadableByItsOwner() throws {
        let directory = makeInstallDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = LocalServerTokenStore.tokenFileURL(installDirectory: directory)
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data("an-old-token".utf8),
            attributes: [.posixPermissions: NSNumber(value: 0o644)]
        )

        XCTAssertTrue(LocalServerTokenStore.writeToken("a-new-token", at: url))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.int16Value, 0o600)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "a-new-token")
    }

    /// A token file that an older build left readable by everyone else is
    /// repaired when the app reads it: the token is written back with the
    /// permissions it is supposed to have. The server rewrites the file at
    /// every start as well, but the app should not leave a secret lying
    /// around until the next start.
    func testAStoredTokenFileIsRepairedWhenItIsTooReadable() throws {
        let directory = makeInstallDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = LocalServerTokenStore.tokenFileURL(installDirectory: directory)
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data("an-old-token".utf8),
            attributes: [.posixPermissions: NSNumber(value: 0o644)]
        )

        let token = LocalServerTokenStore.token(installDirectory: directory)

        XCTAssertEqual(token, "an-old-token")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.int16Value, 0o600)
    }

    /// A token file that cannot be given the permissions it needs is not a
    /// token the app may use, and the app has to say why: the server is
    /// running and healthy while the app sends no token, so "the server could
    /// not be reached" would name the wrong cause.
    func testAFileThatCannotBeRepairedSaysWhy() throws {
        let directory = makeInstallDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = LocalServerTokenStore.tokenFileURL(installDirectory: directory)
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data("an-old-token".utf8),
            attributes: [.posixPermissions: NSNumber(value: 0o644)]
        )
        // A directory that cannot be written to is a file that cannot be
        // replaced, so the repair fails.
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o500)],
            ofItemAtPath: directory.path
        )
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: directory.path
            )
        }

        XCTAssertEqual(
            LocalServerTokenStore.tokenOutcome(installDirectory: directory),
            .unavailable(.fileIsTooReadable)
        )
        XCTAssertNil(LocalServerTokenStore.token(installDirectory: directory))
        XCTAssertTrue(
            LocalServerTokenStore.TokenUnavailable.fileIsTooReadable.explanation.contains("token file")
        )
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
        XCTAssertEqual(LocalServerTokenStore.challengeHeader, fixture.challengeHeader)
        XCTAssertEqual(LocalServerTokenStore.proofHeader, fixture.proofHeader)
        // The three ports have to compute the same proof from the same
        // inputs, or the app and the server would never agree on it.
        XCTAssertEqual(
            LocalServerTokenStore.proof(nonce: fixture.proofVector.nonce, token: fixture.proofVector.token),
            fixture.proofVector.proof
        )

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

    struct ProofVector: Decodable {
        let token: String
        let nonce: String
        let proof: String
    }

    let tokenFileName: String
    let environmentVariable: String
    let authorizationScheme: String
    let challengeHeader: String
    let proofHeader: String
    let proofVector: ProofVector
    let macos: MacOS
}
