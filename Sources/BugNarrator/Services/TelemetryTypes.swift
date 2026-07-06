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
