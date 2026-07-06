import Foundation

enum PermissionRecoveryRefreshOutcome: Equatable {
    case unchanged
    case recovered(AppStatus)
}

enum PermissionSettingsOpenResult: Equatable {
    case opened(URL)
    case failed(String)
}

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
