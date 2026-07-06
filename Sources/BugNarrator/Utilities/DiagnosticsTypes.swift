import OSLog
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
