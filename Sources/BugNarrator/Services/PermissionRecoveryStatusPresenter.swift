import Foundation

@MainActor
final class PermissionRecoveryStatusPresenter {
    private let errorPresenter: AppErrorPresenter

    init(errorPresenter: AppErrorPresenter) {
        self.errorPresenter = errorPresenter
    }

    func present(_ outcome: PermissionRecoveryRefreshOutcome) {
        guard case .recovered(let status) = outcome else {
            return
        }

        errorPresenter.setStatus(status)
    }
}
