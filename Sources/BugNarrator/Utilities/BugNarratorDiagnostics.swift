import Foundation
import OSLog

enum DiagnosticsLogCategory: String, Codable, CaseIterable {
    case recording
    case transcription
    case sessionLibrary = "session-library"
    case export
    case permissions
    case screenshots
    case settings
}

enum DiagnosticsLogLevel: String, Codable, CaseIterable {
    case debug
    case info
    case warning
    case error

    var label: String {
        rawValue.uppercased()
    }

    var osLogType: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        }
    }
}

struct DiagnosticsLogEntry: Codable, Equatable {
    let timestamp: Date
    let level: DiagnosticsLogLevel
    let category: DiagnosticsLogCategory
    let event: String
    let message: String
    let metadata: [String: String]

    init(
        timestamp: Date = Date(),
        level: DiagnosticsLogLevel,
        category: DiagnosticsLogCategory,
        event: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.event = event
        self.message = message
        self.metadata = metadata
    }

    func formattedLine(using formatter: ISO8601DateFormatter = BugNarratorDiagnostics.makeTimestampFormatter()) -> String {
        let metadataText = metadata
            .sorted { lhs, rhs in
                lhs.key < rhs.key
            }
            .map { key, value in
                "\(key)=\(value)"
            }
            .joined(separator: " ")

        if metadataText.isEmpty {
            return "\(formatter.string(from: timestamp)) [\(level.label)] [\(category.rawValue)] \(event) - \(message)"
        }

        return "\(formatter.string(from: timestamp)) [\(level.label)] [\(category.rawValue)] \(event) - \(message) \(metadataText)"
    }
}

actor DiagnosticsLogStore {
    private enum StoragePolicy {
        static let maximumStoredEntries = 500
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageURL: URL
    private var entries: [DiagnosticsLogEntry]

    init(fileManager: FileManager = .default, storageURL: URL? = nil) {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
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
        AppSupportLocation.appDirectory(fileManager: fileManager)
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

struct DiagnosticsLogger: Sendable {
    let category: DiagnosticsLogCategory
    let subsystem: String
    let store: DiagnosticsLogStore

    init(
        category: DiagnosticsLogCategory,
        subsystem: String = BugNarratorDiagnostics.subsystem,
        store: DiagnosticsLogStore = BugNarratorDiagnostics.store
    ) {
        self.category = category
        self.subsystem = subsystem
        self.store = store
    }

    func debug(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        log(.debug, event, message, metadata: metadata)
    }

    func info(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        log(.info, event, message, metadata: metadata)
    }

    func warning(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        log(.warning, event, message, metadata: metadata)
    }

    func error(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        log(.error, event, message, metadata: metadata)
    }

    private func log(
        _ level: DiagnosticsLogLevel,
        _ event: String,
        _ message: String,
        metadata: [String: String]
    ) {
        guard BugNarratorDiagnostics.shouldEmit(level) else {
            return
        }

        let sensitiveValues = DiagnosticsRedactor.sensitiveValues(in: metadata)
        let sanitizedEntry = DiagnosticsLogEntry(
            level: level,
            category: category,
            event: DiagnosticsRedactor.sanitizeFreeformText(event, redactingExactValues: sensitiveValues),
            message: DiagnosticsRedactor.sanitizeFreeformText(message, redactingExactValues: sensitiveValues),
            metadata: DiagnosticsRedactor.sanitizeMetadata(metadata)
        )

        let renderedLine = sanitizedEntry.formattedLine()
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        logger.log(level: level.osLogType, "\(renderedLine, privacy: .public)")

        Task {
            await store.record(sanitizedEntry)
        }
    }
}

enum BugNarratorDiagnostics {
    static let subsystem = "com.abdenterprises.bugnarrator"
    static let store = DiagnosticsLogStore()

    static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static let configuration = DiagnosticsConfiguration()

    static func setDebugModeEnabled(_ enabled: Bool) {
        configuration.setDebugModeEnabled(enabled)
    }

    static func isDebugModeEnabled() -> Bool {
        configuration.isDebugModeEnabled()
    }

    static func activeLogLevel() -> DiagnosticsLogLevel {
        isDebugModeEnabled() ? .debug : .info
    }

    static func shouldEmit(_ level: DiagnosticsLogLevel) -> Bool {
        if level == .debug {
            return isDebugModeEnabled()
        }

        return true
    }

    static func recentLogText(limit: Int = 200) async -> String {
        await store.recentLogText(limit: limit)
    }

    static func exportableRecentLogText(fileManager: FileManager = .default, limit: Int = 200) -> String {
        DiagnosticsLogStore.persistedRecentLogText(
            fileManager: fileManager,
            limit: limit
        )
    }
}

private final class DiagnosticsConfiguration: @unchecked Sendable {
    private let lock = NSLock()
    private var debugModeEnabled = false

    func setDebugModeEnabled(_ enabled: Bool) {
        lock.lock()
        debugModeEnabled = enabled
        lock.unlock()
    }

    func isDebugModeEnabled() -> Bool {
        lock.lock()
        let enabled = debugModeEnabled
        lock.unlock()
        return enabled
    }
}

private enum DiagnosticsRedactor {
    private static let explicitSensitiveKeys: Set<String> = [
        "apiKey",
        "api_key",
        "authorization",
        "token",
        "githubToken",
        "jiraToken",
        "password",
        "secret",
        "transcript",
        "rawTranscript",
        "transcriptText",
        "evidence",
        "evidenceExcerpt",
        "requestBody",
        "responseBody"
    ]

    private static let tokenPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"sk-[A-Za-z0-9_-]+"#),
        try! NSRegularExpression(pattern: #"github_pat_[A-Za-z0-9_]+"#),
        try! NSRegularExpression(pattern: #"gh[pousr]_[A-Za-z0-9]+"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"Bearer\s+[A-Za-z0-9._\-]+"#, options: [.caseInsensitive])
    ]

    static func sensitiveValues(in metadata: [String: String]) -> [String] {
        var values = Set<String>()

        for (key, value) in metadata {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }

            if shouldRedactMetadataValue(for: normalizedKey, value: trimmedValue) {
                values.insert(trimmedValue)
            }
        }

        return values.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs < rhs
            }

            return lhs.count > rhs.count
        }
    }

    static func sanitizeMetadata(_ metadata: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: metadata.map { key, value in
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if shouldRedactMetadataValue(for: normalizedKey, value: value) {
                return (normalizedKey, "<redacted>")
            }

            let sanitizedValue = sanitizeFreeformText(value)
            if sanitizedValue != value {
                return (normalizedKey, "<redacted>")
            }

            return (normalizedKey, sanitizedValue)
        })
    }

    static func sanitizeFreeformText(_ text: String, redactingExactValues exactValues: [String] = []) -> String {
        var sanitized = text
        for pattern in tokenPatterns {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = pattern.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "<redacted>"
            )
        }

        for exactValue in exactValues where !exactValue.isEmpty {
            sanitized = sanitized.replacingOccurrences(of: exactValue, with: "<redacted>")
        }

        return sanitized
    }

    private static func shouldRedactMetadataValue(for key: String, value: String) -> Bool {
        let lowercasedKey = key.lowercased()
        if explicitSensitiveKeys.contains(key) ||
            explicitSensitiveKeys.contains(lowercasedKey) ||
            lowercasedKey.contains("token") ||
            lowercasedKey.contains("apikey") ||
            lowercasedKey.contains("api-key") ||
            lowercasedKey.contains("authorization") ||
            lowercasedKey.contains("password") ||
            lowercasedKey.contains("secret") ||
            lowercasedKey.contains("transcript") {
            return true
        }

        return sanitizeFreeformText(value) != value
    }
}
