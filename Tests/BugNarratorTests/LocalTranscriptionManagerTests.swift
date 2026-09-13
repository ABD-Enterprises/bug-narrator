import AppKit
import CryptoKit
import Darwin
import XCTest
@testable import BugNarrator

final class LocalTranscriptionManagerTests: XCTestCase {
    @MainActor
    func testPendingQuitBlocksActualRecordingStartAndReleasesOnRejection() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let gate = ShutdownTestGate()
        var allowed = true
        let replied = expectation(description: "Rejected quit releases admission")
        let coordinator = AppTerminationCoordinator(
            shouldTerminate: { allowed ? harness.appState.applicationShouldTerminate() : .terminateCancel },
            shutdown: { await gate.wait() },
            setTerminationPending: { harness.appState.setTerminationPending($0) }
        )
        XCTAssertEqual(coordinator.request { result in
            XCTAssertFalse(result)
            replied.fulfill()
        }, .terminateLater)
        // This attempt occurs before the cleanup Task even gets a turn.
        await harness.appState.startSession()
        XCTAssertEqual(harness.audioRecorder.startCallCount, 0)
        XCTAssertTrue(harness.appState.localServerControlsDisabled)
        allowed = false
        await gate.release()
        await fulfillment(of: [replied], timeout: 2)
        XCTAssertFalse(harness.appState.localServerControlsDisabled)
        await harness.appState.startSession()
        XCTAssertEqual(harness.audioRecorder.startCallCount, 1)
    }

    @MainActor
    func testRecordingStartupAndTranscriptionGuardServerActionsAndQuit() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.destination, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: fixture.destination.appendingPathComponent("bugnarrator-transcription"))
        let process = FakeLocalServerProcess()
        var dependencies = LocalTranscriptionManager.Dependencies.live
        dependencies.verify = { _ in }
        dependencies.launch = { _, _, onExit in process.onExit = onExit; return process }
        let manager = LocalTranscriptionManager(directory: fixture.destination, dependencies: dependencies)
        manager.start()
        await waitUntil { manager.running }
        XCTAssertTrue(manager.running)
        harness.audioRecorder.suspendStart = true
        let start = Task { await harness.appState.startSession() }
        await waitUntil { harness.audioRecorder.startCallCount == 1 }
        XCTAssertNil(harness.appState.activeRecordingSession)
        XCTAssertEqual(harness.appState.status.phase, .idle)
        XCTAssertEqual(harness.appState.applicationShouldTerminate(), .terminateCancel)
        harness.appState.stopLocalServer(manager)
        XCTAssertFalse(process.terminated)
        // Remove is guarded even if a process exits naturally during startup.
        process.onExit?(0, "")
        harness.appState.removeLocalServer(manager)
        XCTAssertTrue(manager.installed)
        harness.audioRecorder.resumeStart()
        await start.value
        XCTAssertEqual(harness.appState.applicationShouldTerminate(), .terminateCancel)
        harness.appState.presentationState.setStatus(.transcribing(), error: nil)
        XCTAssertTrue(harness.appState.localServerControlsDisabled)
        XCTAssertEqual(harness.appState.applicationShouldTerminate(), .terminateCancel)
        harness.appState.removeLocalServer(manager)
        XCTAssertTrue(manager.installed)
        harness.appState.presentationState.setStatus(.idle(), error: nil)
        harness.appState.removeLocalServer(manager)
        XCTAssertFalse(manager.installed)
    }

    @MainActor
    func testRetryRemainsProtectedAfterScreenshotChangesPresentationStatus() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        harness.settingsStore.aiProvider = .openAI
        harness.audioRecorder.stopResults = [.success(try harness.makeRecordedAudio(fileName: "retry-admission"))]
        await harness.appState.startSession()
        harness.settingsStore.removeAPIKey()
        await harness.appState.stopSession()
        let session = try XCTUnwrap(harness.transcriptStore.sessions.first)
        harness.settingsStore.apiKey = "restored-key"
        await harness.transcriptionClient.enqueue(.success(TranscriptionResult(text: "Recovered transcript", segments: [])))
        await harness.transcriptionClient.holdTranscription()
        let retry = Task { await harness.appState.retryPendingTranscription(for: session.id) }
        await waitUntil { harness.appState.retryingSessionID != nil }
        await harness.appState.captureScreenshot()
        XCTAssertEqual(harness.appState.status.phase, .error)
        XCTAssertTrue(harness.appState.localServerControlsDisabled)
        XCTAssertEqual(harness.appState.applicationShouldTerminate(), .terminateCancel)
        await harness.appState.startSession()
        XCTAssertEqual(harness.audioRecorder.startCallCount, 1)
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.destination, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: fixture.destination.appendingPathComponent("bugnarrator-transcription"))
        let process = FakeLocalServerProcess()
        var dependencies = LocalTranscriptionManager.Dependencies.live
        dependencies.verify = { _ in }
        dependencies.launch = { _, _, onExit in process.onExit = onExit; return process }
        let manager = LocalTranscriptionManager(directory: fixture.destination, dependencies: dependencies)
        manager.start()
        await waitUntil { manager.running }
        harness.appState.stopLocalServer(manager)
        XCTAssertFalse(process.terminated)
        process.onExit?(0, "")
        harness.appState.removeLocalServer(manager)
        XCTAssertTrue(manager.installed)
        await harness.transcriptionClient.resumeTranscription()
        await retry.value
        XCTAssertFalse(harness.appState.localServerControlsDisabled)
    }

    @MainActor
    func testTerminationVetoDoesNotStartCleanup() {
        let coordinator = AppTerminationCoordinator(shouldTerminate: { .terminateCancel }, shutdown: {
            XCTFail("Recording/transcription veto must precede cleanup")
        })
        XCTAssertEqual(coordinator.request { _ in XCTFail("No deferred reply on veto") }, .terminateCancel)
    }

    @MainActor
    func testAllowedQuitRepliesOnlyAfterCleanup() async {
        let gate = ShutdownTestGate()
        var replyCount = 0
        let replied = expectation(description: "Allowed deferred termination")
        let coordinator = AppTerminationCoordinator(shouldTerminate: { .terminateNow }, shutdown: { await gate.wait() })
        XCTAssertEqual(coordinator.request { allowed in
            XCTAssertTrue(allowed)
            replyCount += 1
            replied.fulfill()
        }, .terminateLater)
        await Task.yield()
        XCTAssertEqual(replyCount, 0)
        await gate.release()
        await fulfillment(of: [replied], timeout: 2)
        XCTAssertEqual(replyCount, 1)
    }

    @MainActor
    func testDuplicateQuitWaitsForCleanupAndRechecksVeto() async {
        let gate = ShutdownTestGate()
        var allowed = true
        var cleanups = 0
        let replied = expectation(description: "One deferred termination reply")
        replied.assertForOverFulfill = true
        let coordinator = AppTerminationCoordinator(shouldTerminate: { allowed ? .terminateNow : .terminateCancel }, shutdown: {
            cleanups += 1
            await gate.wait()
        })
        XCTAssertEqual(coordinator.request { result in
            XCTAssertFalse(result, "Late recording/transcription must veto termination")
            replied.fulfill()
        }, .terminateLater)
        XCTAssertEqual(coordinator.request { _ in XCTFail("Duplicate quit must not reply twice") }, .terminateLater)
        allowed = false
        await gate.release()
        await fulfillment(of: [replied], timeout: 2)
        XCTAssertEqual(cleanups, 1)
    }

    @MainActor
    func testShutdownWaitsForCanceledInstallerCleanup() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove(); MockURLProtocol.requestHandler = nil }
        let assetName = LocalTranscriptionManager.assetName
        let manifest = fixture.manifest
        MockURLProtocol.requestHandler = { @Sendable request in
            let data: Data
            if request.url!.path.contains("releases/download") {
                data = request.url!.path.hasSuffix("checksum") ? manifest : Data("image".utf8)
            } else {
                data = try JSONSerialization.data(withJSONObject: [["draft": false, "prerelease": false, "assets": [
                    ["name": assetName, "size": 5, "browser_download_url": "https://github.com/ABD-Enterprises/bug-narrator/releases/download/v1/image"],
                    ["name": assetName + ".sha256", "size": 64, "browser_download_url": "https://github.com/ABD-Enterprises/bug-narrator/releases/download/v1/checksum"]
                ]]])
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let gate = ShutdownTestGate()
        let installing = expectation(description: "Installer entered")
        let shutdownEntered = expectation(description: "Shutdown entered")
        var dependencies = LocalTranscriptionManager.Dependencies.live
        dependencies.install = { _, _, _, _ in
            installing.fulfill()
            await gate.wait()
            try Task.checkCancellation()
        }
        dependencies.launch = { _, _, _ in XCTFail("Canceled install must not launch"); return FakeLocalServerProcess() }
        let manager = LocalTranscriptionManager(directory: fixture.destination, session: makeMockURLSession(), dependencies: dependencies)
        try XCTSkipUnless(manager.supported, "Server packages require Apple Silicon")
        await manager.discover()
        manager.installAndStart()
        await fulfillment(of: [installing], timeout: 2)
        var finished = false
        let shutdown = Task { shutdownEntered.fulfill(); await manager.shutdown(); finished = true }
        await fulfillment(of: [shutdownEntered], timeout: 2)
        XCTAssertFalse(finished)
        await gate.release()
        await shutdown.value
        XCTAssertTrue(finished)
        XCTAssertFalse(manager.installed)
        XCTAssertFalse(manager.running)
        XCTAssertFalse(manager.busy)
    }

    @MainActor
    func testShutdownWaitsForCanceledStartAndPreventsLaunch() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.destination, withIntermediateDirectories: true)
        try Data("server".utf8).write(to: fixture.destination.appendingPathComponent("bugnarrator-transcription"))
        let gate = ShutdownTestGate()
        let entered = expectation(description: "Verification entered")
        var dependencies = LocalTranscriptionManager.Dependencies.live
        dependencies.verify = { _ in entered.fulfill(); await gate.wait() }
        dependencies.launch = { _, _, _ in XCTFail("Canceled start must not launch"); return FakeLocalServerProcess() }
        let manager = LocalTranscriptionManager(directory: fixture.destination, dependencies: dependencies)
        manager.start()
        await fulfillment(of: [entered], timeout: 2)
        var finished = false
        let shutdown = Task { await manager.shutdown(); finished = true }
        await Task.yield()
        XCTAssertFalse(finished)
        await gate.release()
        await shutdown.value
        XCTAssertTrue(finished)
        XCTAssertFalse(manager.running)
        XCTAssertFalse(manager.busy)
    }

    @MainActor
    func testShutdownWaitsForProcessExitAndAllowsAlreadyExitedWaiters() async throws {
        let fixture = try InstallerFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.destination, withIntermediateDirectories: true)
        try Data("server".utf8).write(to: fixture.destination.appendingPathComponent("bugnarrator-transcription"))
        let process = FakeLocalServerProcess()
        var dependencies = LocalTranscriptionManager.Dependencies.live
        dependencies.verify = { _ in }
        dependencies.launch = { _, _, onExit in process.onExit = onExit; return process }
        let manager = LocalTranscriptionManager(directory: fixture.destination, dependencies: dependencies)
        manager.start()
        for _ in 0..<100 where manager.busy { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(manager.running)
        var finished = false
        let shutdown = Task { await manager.shutdown(); finished = true }
        for _ in 0..<100 where !process.terminated { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(process.terminated)
        XCTAssertFalse(finished)
        process.completeExit()
        process.onExit?(0, "")
        await shutdown.value
        await process.waitForExit()
        XCTAssertTrue(finished)
        XCTAssertFalse(manager.running)
    }

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

    /// Writes an executable Python stand-in for the server binary (`--preload` is
    /// ignored). Python, not sh: bash 3.2 exits 143 when a child it is waiting on
    /// dies of the same TERM the shell received, before any trap runs, so a shell
    /// script cannot model a server that drains after a process-group TERM.
    private func makeServerStandIn(_ body: String) throws -> (binary: URL, ready: URL) {
        // The script lives in its own fresh directory: Python puts the script's
        // directory first on sys.path and lists it on the first import, and a
        // developer's temp directory can hold tens of thousands of entries —
        // enough that the stand-in was still importing `signal` seconds later
        // and died of the TERM. The stand-in signals readiness through a file
        // so the test terminates it only once the handler is installed.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bug-narrator-server-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("server.py")
        let ready = directory.appendingPathComponent("ready")
        try """
        #!/usr/bin/python3
        import signal, sys, time
        \(body)
        open(\"\(ready.path)\", "w").close()
        while True:
            time.sleep(0.05)

        """.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return (url, ready)
    }

    @MainActor
    private func waitForReady(_ ready: URL) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: ready.path) {
            XCTAssertLessThan(Date(), deadline, "stand-in server never became ready")
            guard Date() < deadline else { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    func testServerThatNeedsASecondToDrainAfterTermExitsCleanly() async throws {
        // #1124 cut the grace to 0.5 s, so this child was KILLed (137) mid-drain.
        let (binary, ready) = try makeServerStandIn("signal.signal(signal.SIGTERM, lambda *_: (time.sleep(1), sys.exit(0)))")
        defer { try? FileManager.default.removeItem(at: binary.deletingLastPathComponent()) }
        let exited = expectation(description: "server exits")
        nonisolated(unsafe) var result: (Int32, String)?
        let process = try LocalTranscriptionManager.Dependencies.live.launch(binary, FileManager.default.temporaryDirectory) { status, detail in
            result = (status, detail)
            exited.fulfill()
        }
        try await waitForReady(ready)
        process.terminate()
        await fulfillment(of: [exited], timeout: 5)
        let (status, detail) = try XCTUnwrap(result)
        XCTAssertEqual(status, 0, "a TERM-honouring server that drains within the grace must not be KILLed: \(detail)")
        XCTAssertFalse(detail.contains("bug-narrator-process-lifecycle:"), detail)
    }

    @MainActor
    func testWrapperJobControlNoiseNeverReachesTheExitMessage() async throws {
        // A server that ignores TERM is KILLed after the grace; the shell wrapper's
        // own "Killed: 9" report must not become the user-facing detail.
        let (binary, ready) = try makeServerStandIn("signal.signal(signal.SIGTERM, signal.SIG_IGN)")
        defer { try? FileManager.default.removeItem(at: binary.deletingLastPathComponent()) }
        let exited = expectation(description: "server exits")
        nonisolated(unsafe) var result: (Int32, String)?
        let process = try LocalTranscriptionManager.Dependencies.live.launch(binary, FileManager.default.temporaryDirectory) { status, detail in
            result = (status, detail)
            exited.fulfill()
        }
        try await waitForReady(ready)
        process.terminate()
        await fulfillment(of: [exited], timeout: 6)
        let (status, detail) = try XCTUnwrap(result)
        XCTAssertNotEqual(status, 0)
        XCTAssertFalse(detail.contains("bug-narrator-process-lifecycle:"), detail)
        XCTAssertFalse(detail.contains("Killed: 9"), detail)
    }

    func testCommandTimeoutAndCancellationAreBounded() async throws {
        let start = Date()
        do {
            try await LocalTranscriptionManager.background {
                // This process ignores TERM, so completion proves the lifecycle
                // escalates to KILL instead of leaving an installer helper alive.
                try LocalTranscriptionManager.runCommand("/bin/sh", ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.05)
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

        let childPIDFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("bug-narrator-child-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: childPIDFile) }
        let command = "spawn_child() { trap '' TERM; while :; do sleep 1; done; }; trap 'spawn_child & echo $! > \"\(childPIDFile.path)\"; exit 0' TERM; while :; do sleep 1; done"
        do {
            try await LocalTranscriptionManager.background {
                try LocalTranscriptionManager.runCommand("/bin/sh", ["-c", command], timeout: 0.1)
            }
            XCTFail("Expected process-tree timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        let childPID = try XCTUnwrap(
            Int32(String(contentsOf: childPIDFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        )
        defer { if kill(childPID, 0) == 0 { kill(childPID, SIGKILL) } }
        for _ in 0..<100 where kill(childPID, 0) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotEqual(kill(childPID, 0), 0, "TERM-resistant child survived forced process-tree termination")
    }

}

@MainActor
private final class FakeLocalServerProcess: LocalServerProcess {
    var terminated = false
    var onExit: (@MainActor @Sendable (Int32, String) -> Void)?
    private var exited = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func terminate() { terminated = true }
    func waitForExit() async {
        if exited { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func completeExit() {
        exited = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
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

private actor ShutdownTestGate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

