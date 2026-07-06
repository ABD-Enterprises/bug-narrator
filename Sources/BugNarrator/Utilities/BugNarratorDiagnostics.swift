import Foundation
import OSLog
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

// Thread-safety invariant: the only mutable state (`debugModeEnabled`) is read
// and written exclusively under `lock`, so concurrent access from any thread is
// serialized. The `@unchecked` is therefore sound.
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
