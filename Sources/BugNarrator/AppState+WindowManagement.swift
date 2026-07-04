import AppKit

extension AppState {
    func openTranscriptHistory() {
        appUtilityActions.openTranscriptHistory()
    }

    func openRecordingControls() {
        appUtilityActions.openRecordingControls()
    }

    func openSettings() {
        appUtilityActions.openSettings()
    }

    func requestApplicationTermination() {
        applicationTerminationController.requestApplicationTermination()
    }

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        applicationTerminationController.applicationShouldTerminate()
    }
}
