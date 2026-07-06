import OSLog
import Foundation

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

    func debug(_ event: DiagnosticsEventName, _ message: String, metadata: [String: String] = [:]) {
        debug(event.rawValue, message, metadata: metadata)
    }

    func info(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        log(.info, event, message, metadata: metadata)
    }

    func info(_ event: DiagnosticsEventName, _ message: String, metadata: [String: String] = [:]) {
        info(event.rawValue, message, metadata: metadata)
    }

    func warning(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        log(.warning, event, message, metadata: metadata)
    }

    func warning(_ event: DiagnosticsEventName, _ message: String, metadata: [String: String] = [:]) {
        warning(event.rawValue, message, metadata: metadata)
    }

    func error(_ event: String, _ message: String, metadata: [String: String] = [:]) {
        log(.error, event, message, metadata: metadata)
    }

    func error(_ event: DiagnosticsEventName, _ message: String, metadata: [String: String] = [:]) {
        error(event.rawValue, message, metadata: metadata)
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
