import Foundation

extension AppState {
    // MARK: - Methods

    func refreshPermissionRecoveryState() {
        permissionRecoveryStatusPresenter.present(
            permissionRecoveryController.refreshRecoveryState(
                currentError: currentError,
                statusPhase: status.phase
            )
        )
    }

    // MARK: - Computed properties

    var microphoneRecoveryGuidance: String {
        microphoneRecoveryGuidanceDetails.message
    }

    var microphoneRecoveryLocalTestingNote: String? {
        microphoneRecoveryGuidanceDetails.localTestingNote
    }

    private var microphoneRecoveryGuidanceDetails: MicrophoneRecoveryGuidance {
        permissionRecoveryController.microphoneRecoveryGuidance(currentError: currentError)
    }
}
