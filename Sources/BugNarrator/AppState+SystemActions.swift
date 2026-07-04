import Foundation

extension AppState {
    func openMicrophonePrivacySettings() {
        appUtilityActionPresenter.present(appUtilityActions.openMicrophonePrivacySettings())
    }

    func openScreenRecordingPrivacySettings() {
        appUtilityActionPresenter.present(appUtilityActions.openScreenRecordingPrivacySettings())
    }

    func openSystemAudioPrivacySettings() {
        appUtilityActionPresenter.present(appUtilityActions.openSystemAudioPrivacySettings())
    }

    func checkForUpdates() {
        appUtilityActionPresenter.present(appUtilityActions.checkForUpdates())
    }
}
