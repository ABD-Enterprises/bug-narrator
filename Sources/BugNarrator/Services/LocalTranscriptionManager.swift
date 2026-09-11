import AppKit
import Combine
import CryptoKit
import Foundation

@MainActor
final class LocalTranscriptionManager: ObservableObject {
    static let shared = LocalTranscriptionManager()
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
    private var server: Process?
    private var operation: Task<Void, Never>?
    private var startOperation: Task<Void, Never>?
    private var terminationObserver: AnyCancellable?
    private let session: URLSession

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

    init(directory: URL? = nil, session: URLSession = .shared) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BugNarrator/LocalTranscription", isDirectory: true)
        self.session = session
        installed = FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("bugnarrator-transcription").path)
        terminationObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
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
        guard package == nil, !busy, supported else { return }
        busy = true
        defer { busy = false }
        do {
            let url = URL(string: "https://api.github.com/repos/ABD-Enterprises/bug-narrator/releases?per_page=30")!
            let (data, response) = try await session.data(from: url)
            try Self.requireSuccess(response)
            package = Self.selectPackage(from: try JSONDecoder().decode([Release].self, from: data))
            message = package == nil ? "No compatible signed server release was found. Try again later or choose OpenAI." : ""
        } catch { message = "Could not check server releases: \(error.localizedDescription). Try again." }
    }

    func installAndStart() {
        guard let package, supported, !busy, !installed else { return }
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
                try await Task.detached {
                    try Self.installImage(temporary, checksum: checksum, expectedSize: package.image.size, directory: destination)
                }.value
                self.installed = true
                try Task.checkCancellation()
                self.start()
            } catch { self.message = "Installation failed: \(error.localizedDescription). You can retry." }
        }
    }

    func start() {
        guard installed, server == nil, startOperation == nil else { return }
        busy = true
        let binary = executable
        startOperation = Task {
            defer { busy = false; startOperation = nil }
            do {
                try await Task.detached { try Self.verifyBinary(binary) }.value
                try Task.checkCancellation()
                launchVerifiedServer()
            } catch { message = "Could not start the server: \(error.localizedDescription). Remove and reinstall it if verification failed." }
        }
    }

    private func launchVerifiedServer() {
        do {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--preload"]
            var environment = ProcessInfo.processInfo.environment
            environment["HF_HOME"] = directory.appendingPathComponent("Models").path
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] process in
                let status = process.terminationStatus
                Task { @MainActor in
                    guard let self, self.server === process else { return }
                    self.server = nil
                    self.running = false
                    self.message = status == 0 ? "Local server stopped." : "Local server exited (\(status)). Try starting it again."
                }
            }
            try process.run()
            server = process
            running = true
            message = "Server starting. The first start downloads model weights; recording becomes ready when the server responds."
        } catch { message = "Could not start the server: \(error.localizedDescription). Remove and reinstall it if verification failed." }
    }

    func stop() {
        operation?.cancel()
        startOperation?.cancel()
        if let server, server.isRunning { server.terminate() }
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

    nonisolated private static func verifyBinary(_ binary: URL) throws {
        let values = try binary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure("Invalid server executable") }
        try run("/usr/bin/codesign", ["--verify", "--strict", "-R", publisherRequirement + " and identifier \"bugnarrator-transcription\"", binary.path])
    }

    nonisolated private static func installImage(_ image: URL, checksum: Data, expectedSize: Int64, directory: URL) throws {
        try verifyChecksum(file: image, manifest: checksum, expectedSize: expectedSize)
        try run("/usr/bin/codesign", ["--verify", "--strict", "-R", publisherRequirement, image.path])
        let files = FileManager.default
        let mount = files.temporaryDirectory.appendingPathComponent("BugNarrator-Server-\(UUID().uuidString)")
        try files.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: mount) }
        try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, image.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path]) }
        let source = mount.appendingPathComponent("bugnarrator-transcription")
        try verifyBinary(source)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw Failure("Install directory must not be a symbolic link")
        }
        let staging = directory.appendingPathComponent(".install-\(UUID().uuidString)")
        defer { try? files.removeItem(at: staging) }
        try files.copyItem(at: source, to: staging)
        try verifyBinary(staging)
        try files.moveItem(at: staging, to: directory.appendingPathComponent("bugnarrator-transcription"))
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: data.prefix(2048), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure("\(URL(fileURLWithPath: executable).lastPathComponent) failed: \(detail)")
        }
    }

    struct Failure: LocalizedError {
        let description: String
        init(_ description: String) { self.description = description }
        var errorDescription: String? { description }
    }
}

private final class LocalServerDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
}
