import Combine
import Foundation

@MainActor
final class AppPresentationState: ObservableObject {
    @Published private(set) var status: AppStatus
    @Published private(set) var currentError: AppError?
    @Published private(set) var transientToast: TransientToast?

    init(
        status: AppStatus = .idle(),
        currentError: AppError? = nil,
        transientToast: TransientToast? = nil
    ) {
        self.status = status
        self.currentError = currentError
        self.transientToast = transientToast
    }

    func setStatus(_ status: AppStatus, error: AppError? = nil) {
        self.status = status
        currentError = error
    }

    func showToast(_ toast: TransientToast) {
        transientToast = toast
    }

    func dismissToast() {
        transientToast = nil
    }
}
