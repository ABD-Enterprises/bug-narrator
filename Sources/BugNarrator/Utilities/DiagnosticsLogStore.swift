import Foundation
import OSLog

actor DiagnosticsLogStore {
    private enum StoragePolicy {
        static let maximumStoredEntries = 500
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageURL: URL
    private let flushInterval: Duration
    private var entries: [DiagnosticsLogEntry]
    private var isDirty = false
    private var pendingFlushTask: Task<Void, Never>?

    init(fileManager: FileManager = .default, storageURL: URL? = nil, flushInterval: Duration = .seconds(1)) {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.flushInterval = flushInterval
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        self.entries = Self.loadEntries(
            from: self.storageURL,
            fileManager: fileManager,
            decoder: decoder
        )
    }

    func record(_ entry: DiagnosticsLogEntry) {
        entries.append(entry)
        if entries.count > StoragePolicy.maximumStoredEntries {
            entries.removeFirst(entries.count - StoragePolicy.maximumStoredEntries)
        }
        // Coalesce writes: rewriting the whole (up to 500-entry) file on every log
        // line is wasteful under bursty logging. Mark dirty and persist on a
        // debounce; flush() forces an immediate write for shutdown/export.
        isDirty = true
        scheduleFlush()
    }

    /// Persists immediately if there are unwritten entries. Call on app
    /// background/terminate so recent logs survive a quit between debounce ticks.
    func flush() {
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        if isDirty {
            isDirty = false
            persist()
        }
    }

    private func scheduleFlush() {
        guard pendingFlushTask == nil else {
            return
        }
        pendingFlushTask = Task { [weak self, flushInterval] in
            try? await Task.sleep(for: flushInterval)
            // If flush()/clear() cancelled this task, do not run: a stale task
            // could otherwise clobber a newer pending task scheduled meanwhile.
            if Task.isCancelled {
                return
            }
            await self?.flushPending()
        }
    }

    private func flushPending() {
        pendingFlushTask = nil
        guard isDirty else {
            return
        }
        isDirty = false
        persist()
    }

    func recentEntries(limit: Int = 200) -> [DiagnosticsLogEntry] {
        Array(entries.suffix(limit))
    }

    func recentLogText(limit: Int = 200) -> String {
        let lines = recentEntries(limit: limit).map { $0.formattedLine() }
        if lines.isEmpty {
            return "No recent BugNarrator diagnostics logs were captured."
        }

        return lines.joined(separator: "\n") + "\n"
    }

    func clear() {
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        isDirty = false
        entries = []
        try? fileManager.removeItem(at: storageURL)
    }

    private func persist() {
        let directoryURL = storageURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        do {
            let data = try encoder.encode(entries)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            // Keep diagnostics best-effort and local-only.
        }
    }

    private static func loadEntries(
        from storageURL: URL,
        fileManager: FileManager,
        decoder: JSONDecoder
    ) -> [DiagnosticsLogEntry] {
        guard fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let entries = try? decoder.decode([DiagnosticsLogEntry].self, from: data) else {
            return []
        }

        return entries
    }

    static func defaultStorageURL(fileManager: FileManager) -> URL {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return fileManager.temporaryDirectory
                .appendingPathComponent("BugNarratorTestDiagnostics", isDirectory: true)
                .appendingPathComponent("recent-log-\(ProcessInfo.processInfo.processIdentifier).json")
        }

        return AppSupportLocation.appDirectory(fileManager: fileManager)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("recent-log.json")
    }

    static func persistedRecentLogText(
        fileManager: FileManager = .default,
        storageURL: URL? = nil,
        limit: Int = 200
    ) -> String {
        let decoder = JSONDecoder()
        let resolvedStorageURL = storageURL ?? defaultStorageURL(fileManager: fileManager)
        let entries = loadEntries(
            from: resolvedStorageURL,
            fileManager: fileManager,
            decoder: decoder
        )
        let lines = Array(entries.suffix(limit)).map { $0.formattedLine() }
        if lines.isEmpty {
            return "No recent BugNarrator diagnostics logs were captured."
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
