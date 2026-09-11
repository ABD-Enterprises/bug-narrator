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
    @MainActor
    func testDiscoveryFindsServerOnSecondPage() async throws {
        let image = LocalTranscriptionManager.assetName
        MockURLProtocol.requestHandler = { @Sendable request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!
            let releases: [[String: Any]] = page == "1"
                ? Array(repeating: ["draft": false, "prerelease": false, "assets": []], count: 30)
                : [["draft": false, "prerelease": false, "assets": [
                    ["name": image, "size": 100, "browser_download_url": "https://github.com/ABD-Enterprises/bug-narrator/releases/download/server/a"],
                    ["name": image + ".sha256", "size": 64, "browser_download_url": "https://github.com/ABD-Enterprises/bug-narrator/releases/download/server/b"]
                ]]]
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, try JSONSerialization.data(withJSONObject: releases))
        }
        defer { MockURLProtocol.requestHandler = nil }
        let manager = LocalTranscriptionManager(session: makeMockURLSession())
        try XCTSkipUnless(manager.supported, "Server packages require Apple Silicon")
        await manager.discover()
        XCTAssertNotNil(manager.package)
        XCTAssertFalse(manager.busy)
    }

    @MainActor
    func testStartVerifiesBeforeLaunchAndStopTracksExit() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.destination, withIntermediateDirectories: true)
        try Data("server".utf8).write(to: fixture.destination.appendingPathComponent("bugnarrator-transcription"))
        let process = FakeLocalServerProcess()
        var dependencies = LocalTranscriptionManager.Dependencies.live
        dependencies.verify = { _ in }
        dependencies.launch = { _, _, onExit in
            process.onExit = onExit
            return process
        }
        let manager = LocalTranscriptionManager(directory: fixture.destination, dependencies: dependencies)
        manager.start()
        for _ in 0..<100 where manager.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(manager.running)
        manager.stop()
        XCTAssertTrue(process.terminated)
        process.onExit?(1, "Model download failed: disk full")
        XCTAssertFalse(manager.running)
        XCTAssertTrue(manager.message.contains("disk full"))
        manager.remove()
        XCTAssertFalse(manager.installed)
    }

    @MainActor
    func testSignatureRejectionDoesNotLaunch() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.destination, withIntermediateDirectories: true)
        try Data("unsigned".utf8).write(to: fixture.destination.appendingPathComponent("bugnarrator-transcription"))
        var dependencies = LocalTranscriptionManager.Dependencies.live
        dependencies.launch = { _, _, _ in
            XCTFail("Unverified binary must never launch")
            return FakeLocalServerProcess()
        }
        let manager = LocalTranscriptionManager(directory: fixture.destination, dependencies: dependencies)
        manager.start()
        for _ in 0..<200 where manager.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(manager.busy)
        XCTAssertFalse(manager.running)
        XCTAssertTrue(manager.message.contains("Could not start"))
    }

    func testInstallerCommitsVerifiedBinaryAndDetaches() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        try await LocalTranscriptionManager.background {
            try fixture.install()
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("bugnarrator-transcription").path))
        XCTAssertTrue(fixture.detached)
    }

    func testInstallerSignatureRejectionCleansMountWithoutCommitting() async throws {
        let fixture = try InstallerFixture(rejectBinary: true)
        defer { fixture.remove() }
        do {
            try await LocalTranscriptionManager.background { try fixture.install() }
            XCTFail("Expected signature rejection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("signature")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("bugnarrator-transcription").path))
        XCTAssertTrue(fixture.detached)
    }

    func testInstallerCancellationBeforeCommitCleansStagingAndMount() async throws {
        let fixture = try InstallerFixture(pauseBeforeCommit: true)
        defer { fixture.remove() }
        let worker = Task { try await LocalTranscriptionManager.background { try fixture.install() } }
        // The command double pauses at staging verification, immediately before commit.
        for _ in 0..<200 where !fixture.paused { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(fixture.paused)
        worker.cancel()
        fixture.resume.signal()
        do { try await worker.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("bugnarrator-transcription").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path), [])
        XCTAssertTrue(fixture.detached)
    }

    @MainActor
    func testRealProcessReportsStartupStderr() async throws {
        let exited = expectation(description: "CLI process exits with diagnostics")
        // ls is a terminal-only fixture; --preload is deliberately invalid.
        let process = try LocalTranscriptionManager.Dependencies.live.launch(
            URL(fileURLWithPath: "/bin/ls"), FileManager.default.temporaryDirectory
        ) { status, detail in
            XCTAssertNotEqual(status, 0)
            XCTAssertFalse(detail.isEmpty)
            XCTAssertLessThanOrEqual(detail.utf8.count, 2054)
            exited.fulfill()
        }
        await fulfillment(of: [exited], timeout: 3)
        withExtendedLifetime(process) {}
    }

    func testCommandTimeoutAndCancellationAreBounded() async throws {
        let start = Date()
        do {
            try await LocalTranscriptionManager.background {
                try LocalTranscriptionManager.runCommand("/bin/sleep", ["10"], timeout: 0.05)
            }
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        let worker = Task { try await LocalTranscriptionManager.background {
            try LocalTranscriptionManager.runCommand("/bin/sleep", ["10"], timeout: 60)
        } }
        try await Task.sleep(for: .milliseconds(30))
        worker.cancel()
        do { try await worker.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
    }

}

@MainActor
private final class FakeLocalServerProcess: LocalServerProcess {
    var terminated = false
    var onExit: (@MainActor @Sendable (Int32, String) -> Void)?
    func terminate() { terminated = true }
}

private final class InstallerFixture: @unchecked Sendable {
    let root: URL
    let destination: URL
    let image: URL
    let manifest: Data
    let resume = DispatchSemaphore(value: 0)
    private let pauseBeforeCommit: Bool
    private let rejectBinary: Bool
    private let lock = NSLock()
    private var didPause = false
    private var didDetach = false
    var paused: Bool { lock.withLock { didPause } }
    var detached: Bool { lock.withLock { didDetach } }

    init(pauseBeforeCommit: Bool = false, rejectBinary: Bool = false) throws {
        self.rejectBinary = rejectBinary
        self.pauseBeforeCommit = pauseBeforeCommit
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        destination = root.appendingPathComponent("installed")
        image = root.appendingPathComponent("image")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data("image".utf8)
        try data.write(to: image)
        manifest = Data(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().utf8)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func install() throws {
        try LocalTranscriptionManager.installImage(image, checksum: manifest, expectedSize: 5, directory: destination) { command, args in
            if command == "/usr/bin/hdiutil", args.first == "attach" {
                let mount = URL(fileURLWithPath: args[4])
                try Data("verified server".utf8).write(to: mount.appendingPathComponent("bugnarrator-transcription"))
            } else if command == "/usr/bin/hdiutil", args.first == "detach" {
                self.lock.withLock { self.didDetach = true }
            } else if command == "/usr/bin/codesign", args.last!.hasSuffix("bugnarrator-transcription"), self.rejectBinary {
                throw LocalTranscriptionManager.Failure("Rejected binary signature")
            } else if command == "/usr/bin/codesign", args.last!.contains(".install-"), self.pauseBeforeCommit {
                self.lock.withLock { self.didPause = true }
                guard self.resume.wait(timeout: .now() + 3) == .success else {
                    throw LocalTranscriptionManager.Failure("Test installer was not resumed")
                }
            }
        }
    }
}
