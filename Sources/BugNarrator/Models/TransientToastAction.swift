import Foundation

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
