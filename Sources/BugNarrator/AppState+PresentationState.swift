import Foundation

extension AppState {
    var status: AppStatus {
        presentationState.status
    }

    var currentError: AppError? {
        presentationState.currentError
    }

    var transientToast: TransientToast? {
        presentationState.transientToast
    }
}
