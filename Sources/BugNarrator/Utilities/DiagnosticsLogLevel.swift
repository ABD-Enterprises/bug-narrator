import OSLog
import Foundation

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
