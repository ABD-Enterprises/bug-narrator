import Foundation

struct PrivacyDataExportDiagnosticsSnapshot: Codable, Equatable {
    let appName: String
    let versionDescription: String
    let macOSVersion: String
    let architecture: String
    let activeTranscriptionModel: String
    let issueExtractionModel: String
    let logLevel: String
    let debugModeEnabled: Bool
    let recentTelemetryEvents: [OperationalTelemetryEvent]
    let recentDiagnosticsLog: String
    let exportHistory: [ExportReceipt]
}
