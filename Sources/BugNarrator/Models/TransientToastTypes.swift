import Foundation

enum TransientToastStyle: String, Equatable {
    case success
    case informational

    var symbolName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .informational:
            return "xmark.circle"
        }
    }
}

