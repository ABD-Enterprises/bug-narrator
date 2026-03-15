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

struct TransientToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: TransientToastStyle

    init(message: String, style: TransientToastStyle = .success) {
        self.message = message
        self.style = style
    }
}
