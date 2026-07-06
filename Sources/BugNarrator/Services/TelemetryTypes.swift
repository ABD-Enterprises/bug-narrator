import Foundation

struct OperationalTelemetryEvent: Codable, Equatable {
    let timestamp: Date
    let name: String
    let metadata: [String: String]

    init(timestamp: Date = Date(), name: String, metadata: [String: String] = [:]) {
        self.timestamp = timestamp
        self.name = name
        self.metadata = metadata
    }
}

struct TelemetryEventName: RawRepresentable, ExpressibleByStringLiteral, Equatable, Hashable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }
}

enum TelemetryEvent {
    static let appError = TelemetryEventName("app_error")
    static let recordingStarted = TelemetryEventName("recording_started")
    static let transcriptionCompleted = TelemetryEventName("transcription_completed")
    static let privacyDataExported = TelemetryEventName("privacy_data_exported")
}

extension TelemetryEventName {
    static let appError = TelemetryEvent.appError
    static let recordingStarted = TelemetryEvent.recordingStarted
    static let transcriptionCompleted = TelemetryEvent.transcriptionCompleted
    static let privacyDataExported = TelemetryEvent.privacyDataExported
}
