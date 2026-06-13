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

struct TransientToastAction: Equatable {
    let title: String
    let accessibilityLabel: String
    let perform: @MainActor () -> Void

    init(
        title: String,
        accessibilityLabel: String? = nil,
        perform: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel ?? title
        self.perform = perform
    }

    static func == (lhs: TransientToastAction, rhs: TransientToastAction) -> Bool {
        lhs.title == rhs.title && lhs.accessibilityLabel == rhs.accessibilityLabel
    }
}

struct TransientToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: TransientToastStyle
    let action: TransientToastAction?

    init(
        message: String,
        style: TransientToastStyle = .success,
        action: TransientToastAction? = nil
    ) {
        self.message = message
        self.style = style
        self.action = action
    }
}
