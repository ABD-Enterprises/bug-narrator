import Foundation

enum DiagnosticsLogCategory: String, Codable, CaseIterable {
    case recording
    case transcription
    case sessionLibrary = "session-library"
    case export
    case permissions
    case screenshots
    case settings
}
