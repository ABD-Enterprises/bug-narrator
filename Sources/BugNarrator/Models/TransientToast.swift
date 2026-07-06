import Foundation

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
