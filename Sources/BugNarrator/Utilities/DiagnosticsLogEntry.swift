import Foundation

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
