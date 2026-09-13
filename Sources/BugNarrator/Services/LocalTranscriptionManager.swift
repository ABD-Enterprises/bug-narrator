import AppKit
import Combine
import CryptoKit
import Darwin
import Foundation

@MainActor
final class LocalTranscriptionManager: ObservableObject {
    static let assetName = "bugnarrator-transcription-macos-arm64.dmg"
    nonisolated static let publisherRequirement = "=anchor apple generic and certificate leaf[subject.OU] = \"2R4WAH4R53\""

    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let size: Int64
        let browser_download_url: URL
    }
    struct Release: Decodable, Sendable {
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    struct Package: Equatable, Sendable {
        let image: Asset
        let checksum: Asset
    }

    @Published private(set) var package: Package?
    @Published private(set) var progress: Double?
    @Published private(set) var busy = false
    @Published private(set) var installed: Bool
    @Published private(set) var running = false
    @Published private(set) var message = ""
    let directory: URL
    private var server: (any LocalServerProcess)?
    private var operation: Task<Void, Never>?
    private var startOperation: Task<Void, Never>?
    private var shuttingDown = false
    private var terminationObserver: AnyCancellable?
    private let session: URLSession
    private let dependencies: Dependencies

    var executable: URL { directory.appendingPathComponent("bugnarrator-transcription") }
    var downloadSize: String {
        package.map { ByteCountFormatter.string(fromByteCount: $0.image.size, countStyle: .file) } ?? "about 136 MB"
    }
    var supported: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    init(directory: URL? = nil, session: URLSession = .shared, dependencies: Dependencies = .live) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BugNarrator/LocalTranscription", isDirectory: true)
        self.session = session
        self.dependencies = dependencies
        installed = FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("bugnarrator-transcription").path)
        terminationObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
    }

    static func isolated(directory: URL) -> LocalTranscriptionManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IsolatedLocalServerURLProtocol.self]
        return LocalTranscriptionManager(directory: directory, session: URLSession(configuration: configuration), dependencies: .isolated)
    }

    static func selectPackage(from releases: [Release]) -> Package? {
        for release in releases where !release.draft && !release.prerelease {
            if let image = release.assets.first(where: { $0.name == assetName }),
               let checksum = release.assets.first(where: { $0.name == assetName + ".sha256" }),
               image.size > 0, image.size < 1_000_000_000,
               checksum.size > 0, checksum.size < 4096,
               trustedAssetURL(image.browser_download_url), trustedAssetURL(checksum.browser_download_url) {
                return Package(image: image, checksum: checksum)
            }
        }
        return nil
    }

    static func trustedAssetURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil &&
            url.path.hasPrefix("/ABD-Enterprises/bug-narrator/releases/download/")
    }

    func discover() async {
        guard package == nil, !busy, supported, !shuttingDown else { return }
        busy = true
        defer { busy = false }
        do {
            // App and server releases have independent cadences. Search bounded pages.
            for page in 1...20 {
                try Task.checkCancellation()
                let url = URL(string: "https://api.github.com/repos/ABD-Enterprises/bug-narrator/releases?per_page=30&page=\(page)")!
                let (data, response) = try await session.data(from: url)
                try Self.requireSuccess(response)
                let releases = try JSONDecoder().decode([Release].self, from: data)
                if let found = Self.selectPackage(from: releases) {
                    package = found
                    message = ""
                    return
                }
                if releases.count < 30 {
                    message = "No compatible signed server release was found. Try again later or choose OpenAI."
                    return
                }
            }
            message = "Server release search reached its limit. Check the project releases or choose OpenAI."

        } catch { message = "Could not check server releases: \(error.localizedDescription). Try again." }
    }

    func installAndStart() {
        guard let package, supported, !busy, !installed, !shuttingDown else { return }
        busy = true
        progress = 0
        message = "Downloading the local server…"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = self.startOperation != nil; self.progress = nil; self.operation = nil }
            do {
                let delegate = LocalServerDownloadProgress { [weak self] fraction in
                    Task { @MainActor in self?.progress = fraction }
                }
                let (checksum, checksumResponse) = try await self.session.data(from: package.checksum.browser_download_url)
                try Self.requireSuccess(checksumResponse)
                guard checksum.count < 4096 else { throw Failure("Invalid checksum manifest") }
                let (temporary, response) = try await self.session.download(from: package.image.browser_download_url, delegate: delegate)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Self.requireSuccess(response)
                try Task.checkCancellation()
                self.message = "Verifying and installing the signed server…"
                let destination = self.directory
                try await self.dependencies.install(temporary, checksum, package.image.size, destination)
                self.installed = true
                try Task.checkCancellation()
                self.start()
            } catch is CancellationError {
                self.message = "Installation canceled. You can retry."
            } catch { self.message = "Installation failed: \(error.localizedDescription). You can retry." }
        }
    }

    func start() {
        guard installed, server == nil, startOperation == nil, !shuttingDown else { return }
        busy = true
        let binary = executable
        startOperation = Task {
            defer { busy = false; startOperation = nil }
            do {
                try await dependencies.verify(binary)
                try Task.checkCancellation()
                launchVerifiedServer()
            } catch is CancellationError {
                message = "Server start canceled."
            } catch { message = "Could not start the server: \(error.localizedDescription). Remove and reinstall it if verification failed." }
        }
    }

    private func launchVerifiedServer() {
        do {
            let process = try dependencies.launch(executable, directory.appendingPathComponent("Models")) { [weak self] status, detail in
                guard let self else { return }
                self.server = nil
                self.running = false
                self.message = status == 0 ? "Local server stopped." : "Local server exited (\(status)). \(detail.isEmpty ? "Try starting it again." : detail)"
            }
            server = process
            running = true
            message = "Server starting. The first start downloads model weights; recording becomes ready when the server responds."
        } catch { message = "Could not start the server: \(error.localizedDescription). Remove and reinstall it if verification failed." }
    }

    func stop() {
        operation?.cancel()
        startOperation?.cancel()
        server?.terminate()
    }

    func shutdown() async {
        shuttingDown = true
        defer { shuttingDown = false }
        let installing = operation
        let starting = startOperation
        let process = server
        stop()
        // Cancellation requests alone are insufficient: await detach/staging cleanup
        // and the bounded SIGTERM/SIGKILL process shutdown before the OS exits.
        await installing?.value
        await starting?.value
        await process?.waitForExit()
    }

    func remove() {
        guard !busy, server == nil, startOperation == nil else { return }
        do {
            try FileManager.default.removeItem(at: directory)
            installed = false
            message = "Local server and its managed model cache removed."
        } catch { message = "Could not remove the local server: \(error.localizedDescription)" }
    }

    private static func requireSuccess(_ response: URLResponse) throws {
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure("The download server returned an unsuccessful response")
        }
    }

    nonisolated static func verifyChecksum(file: URL, manifest: Data, expectedSize: Int64) throws {
        guard manifest.count < 4096,
              let text = String(data: manifest, encoding: .utf8),
              let expected = text.split(whereSeparator: \.isWhitespace).first,
              expected.count == 64, expected.allSatisfy({ $0.isHexDigit }),
              (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize == Int(expectedSize) else {
            throw Failure("Invalid checksum manifest or download size")
        }
        let contents = try Data(contentsOf: file, options: .mappedIfSafe)
        let actual = SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else { throw Failure("The server download failed its SHA-256 check") }
    }

    nonisolated static func verifyBinary(_ binary: URL, command: Command = run) throws {
        let values = try binary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure("Invalid server executable") }
        try command("/usr/bin/codesign", ["--verify", "--strict", "-R", publisherRequirement + " and identifier \"bugnarrator-transcription\"", binary.path])
    }

    nonisolated static func installImage(_ image: URL, checksum: Data, expectedSize: Int64, directory: URL, command: Command = run) throws {
        try Task.checkCancellation()
        try verifyChecksum(file: image, manifest: checksum, expectedSize: expectedSize)
        try command("/usr/bin/codesign", ["--verify", "--strict", "-R", publisherRequirement, image.path])
        try Task.checkCancellation()
        let files = FileManager.default
        let mount = files.temporaryDirectory.appendingPathComponent("BugNarrator-Server-\(UUID().uuidString)")
        try files.createDirectory(at: mount, withIntermediateDirectories: true)
        // Even an interrupted attach can have mounted the image. Cleanup ignores task
        // cancellation, has its own timeout, and must detach before removing the path.
        var detached = false
        defer {
            if !detached {
                detached = (try? command("/usr/bin/hdiutil", ["detach", "-force", mount.path])) != nil
            }
            if detached { try? files.removeItem(at: mount) }
        }
        try command("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, image.path])
        try Task.checkCancellation()
        let source = mount.appendingPathComponent("bugnarrator-transcription")
        try verifyBinary(source, command: command)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw Failure("Install directory must not be a symbolic link")
        }
        let staging = directory.appendingPathComponent(".install-\(UUID().uuidString)")
        defer { try? files.removeItem(at: staging) }
        try Task.checkCancellation()
        try files.copyItem(at: source, to: staging)
        try verifyBinary(staging, command: command)
        try command("/usr/bin/hdiutil", ["detach", mount.path])
        detached = true
        try Task.checkCancellation()
        try files.moveItem(at: staging, to: directory.appendingPathComponent("bugnarrator-transcription"))
    }

    typealias Command = @Sendable (String, [String]) throws -> Void

    nonisolated static func run(_ executable: String, _ arguments: [String]) throws {
        try runCommand(executable, arguments, timeout: 60)
    }

    nonisolated static func runCommand(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws {
        let cleanup = executable == "/usr/bin/hdiutil" && arguments.first == "detach"
        if !cleanup { try Task.checkCancellation() }
        let lifecycle = LocalServerProcessLifecycle(executable: executable, arguments: arguments)
        let process = lifecycle.process
        defer { lifecycle.finishDiagnostics() }
        try lifecycle.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if (!cleanup && Task.isCancelled) || Date() >= deadline {
                lifecycle.terminateAndWait()
                if !cleanup && Task.isCancelled { throw CancellationError() }
                throw Failure("\(URL(fileURLWithPath: executable).lastPathComponent) timed out. Retry installation.")
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        lifecycle.finishDiagnostics()
        guard process.terminationStatus == 0 else {
            throw Failure("\(URL(fileURLWithPath: executable).lastPathComponent) failed: \(lifecycle.diagnosticText)")
        }
    }

    nonisolated static func background(_ action: @escaping @Sendable () throws -> Void) async throws {
        let worker = Task.detached { try action() }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    struct Dependencies: Sendable {
        var install: @Sendable (URL, Data, Int64, URL) async throws -> Void
        var verify: @Sendable (URL) async throws -> Void
        var launch: @MainActor @Sendable (URL, URL, @escaping @MainActor @Sendable (Int32, String) -> Void) throws -> any LocalServerProcess

        static let isolated = Dependencies(
            install: { _, _, _, _ in throw Failure("Server installation is disabled in the isolated runtime.") },
            verify: { _ in throw Failure("Server launch is disabled in the isolated runtime.") },
            launch: { _, _, _ in throw Failure("Server launch is disabled in the isolated runtime.") }
        )

        static let live = Dependencies(
            install: { image, checksum, size, directory in
                try await background { try installImage(image, checksum: checksum, expectedSize: size, directory: directory) }
            },
            verify: { binary in try await background { try verifyBinary(binary) } },
            launch: { binary, models, onExit in try ManagedLocalServerProcess(binary: binary, models: models, onExit: onExit) }
        )
    }

    struct Failure: LocalizedError {
        let description: String
        init(_ description: String) { self.description = description }
        var errorDescription: String? { description }
    }
}

// Thread-safety invariant: the only stored property is `progress`, an immutable
// `@Sendable` closure, so there is no mutable state to race on. The delegate
// callbacks arrive on URLSession's delegate queue and only invoke that closure.
// `@unchecked` exists solely because NSObject subclasses cannot be checked
// structurally; nothing here needs a lock.
private final class LocalServerDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
}

@MainActor
protocol LocalServerProcess: AnyObject {
    func waitForExit() async
    func terminate()
}

// Thread-safety invariant: every access to the mutable state (`data`, `finished`)
// is serialized through `lock` — `append` and `text` take it directly,
// `finishReading` uses `withLock`. `ended` is a DispatchSemaphore, safe by
// construction. The readability handler runs on a background queue and only
// calls the locked `append`, clears its own handler, and signals `ended` — none
// of which touches the buffer unlocked — so the pipe reader and the caller of
// `text` never race on it. Hence the `@unchecked` is sound.
private final class LocalServerDiagnostic: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let ended = DispatchSemaphore(value: 0)
    private var finished = false
    func read(from pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let next = handle.availableData
            if next.isEmpty {
                handle.readabilityHandler = nil
                ended.signal()
            } else { append(next) }
        }
    }
    func finishReading(_ pipe: Pipe) {
        let first = lock.withLock {
            if finished { return false }
            finished = true
            return true
        }
        guard first else { return }
        _ = ended.wait(timeout: .now() + 0.2)
        pipe.fileHandleForReading.readabilityHandler = nil
    }
    func append(_ next: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(next)
        if data.count > 2048 { data = Data(data.suffix(2048)) }
    }
    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Every locally launched process follows this lifecycle: start its bounded stderr
// drain, wait for normal completion, and on cancellation or timeout send TERM,
// allow a short grace period, then send KILL and wait for exit. Keeping that
// policy here prevents either installer helpers or the long-lived server from
// acquiring a different shutdown contract.
private enum LocalServerProcessLifecycleError: LocalizedError {
    case processIsolationFailed

    var errorDescription: String? { "Could not isolate the local helper process lifecycle" }
}

private final class LocalServerProcessLifecycle: @unchecked Sendable {
    let process = Process()
    private let errors = Pipe()
    private let startupInput = Pipe()
    private let processGroupOutput = Pipe()
    private let diagnostic = LocalServerDiagnostic()
    private var processGroup: pid_t?

    init(executable: String, arguments: [String], environment: [String: String]? = nil) {
        // A non-interactive shell with job control puts its background job in a
        // dedicated process group. The first stdout line is the owned group ID;
        // the launched program's stdout remains discarded as before.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "set -m; ( read ready && exec \"$@\" ) >/dev/null & child=$!; set +m; printf '%s\\n' \"$child\"; exec 1>/dev/null; wait \"$child\"",
            "bug-narrator-process-lifecycle",
            executable,
        ] + arguments
        process.environment = environment
        process.standardInput = startupInput
        process.standardOutput = processGroupOutput
        process.standardError = errors
        diagnostic.read(from: errors)
    }

    func run() throws {
        do {
            try process.run()
            errors.fileHandleForWriting.closeFile()
            processGroupOutput.fileHandleForWriting.closeFile()
            let data = processGroupOutput.fileHandleForReading.readData(ofLength: 32)
            let value = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let group = pid_t(value), group > 1, group != getpgrp() else {
                process.terminate()
                process.waitUntilExit()
                throw LocalServerProcessLifecycleError.processIsolationFailed
            }
            guard getpgid(group) == group else {
                startupInput.fileHandleForWriting.closeFile()
                process.terminate()
                process.waitUntilExit()
                throw LocalServerProcessLifecycleError.processIsolationFailed
            }
            processGroup = group
            startupInput.fileHandleForWriting.write(Data("ready\n".utf8))
            startupInput.fileHandleForWriting.closeFile()
        } catch {
            try? startupInput.fileHandleForWriting.close()
            errors.fileHandleForReading.readabilityHandler = nil
            throw error
        }
    }

    func terminateAndWait() {
        let group = processGroup
        guard process.isRunning || group.map(Self.isGroupAlive) == true else { return }
        if let group, Self.isGroupAlive(group) { kill(-group, SIGTERM) }
        process.terminate()
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline,
              process.isRunning || group.map(Self.isGroupAlive) == true {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if let group, Self.isGroupAlive(group) { kill(-group, SIGKILL) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }

    private static func isGroupAlive(_ group: pid_t) -> Bool {
        kill(-group, 0) == 0 || errno == EPERM
    }

    func finishDiagnostics() { diagnostic.finishReading(errors) }
    var diagnosticText: String { diagnostic.text }
}

@MainActor
private final class ManagedLocalServerProcess: LocalServerProcess {
    private let lifecycle: LocalServerProcessLifecycle
    private var terminationTask: Task<Void, Never>?
    init(binary: URL, models: URL, onExit: @escaping @MainActor @Sendable (Int32, String) -> Void) throws {
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HOME"] = models.path
        let lifecycle = LocalServerProcessLifecycle(executable: binary.path, arguments: ["--preload"], environment: environment)
        self.lifecycle = lifecycle
        let process = lifecycle.process
        process.terminationHandler = { [weak lifecycle] process in
            guard let lifecycle else { return }
            lifecycle.finishDiagnostics()
            let status = process.terminationStatus
            let detail = lifecycle.diagnosticText
            Task { @MainActor in onExit(status, detail) }
        }
        try lifecycle.run()
    }
    func waitForExit() async {
        while lifecycle.process.isRunning {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await terminationTask?.value
    }

    func terminate() {
        guard terminationTask == nil else { return }
        let lifecycle = lifecycle
        terminationTask = Task.detached { lifecycle.terminateAndWait() }
    }
}

/// An instance-scoped transport barrier: test controls never open a real connection.
private final class IsolatedLocalServerURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
