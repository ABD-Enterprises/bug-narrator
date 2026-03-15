import Darwin
import SwiftUI

@main
struct BugNarratorApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var transcriptStore: TranscriptStore
    @StateObject private var appState: AppState

    private let windowCoordinator: WindowCoordinator

    init() {
        let runtimeEnvironment = AppRuntimeEnvironment()

        if !runtimeEnvironment.shouldBypassSingleInstanceEnforcement {
            guard SingleInstanceController.enforcePrimaryInstance() else {
                exit(EXIT_SUCCESS)
            }
        }

        let settingsStore = SettingsStore()
        let transcriptStore = TranscriptStore()
        let appState = AppState(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            runtimeEnvironment: runtimeEnvironment
        )
        let windowCoordinator = WindowCoordinator(
            appState: appState,
            transcriptStore: transcriptStore,
            settingsStore: settingsStore
        )

        appState.showTranscriptWindow = { [weak windowCoordinator] in
            windowCoordinator?.showTranscriptWindow()
        }
        appState.showSettingsWindow = { [weak windowCoordinator] in
            windowCoordinator?.showSettingsWindow()
        }
        appState.showAboutWindow = { [weak windowCoordinator] in
            windowCoordinator?.showAboutWindow()
        }
        appState.showChangelogWindow = { [weak windowCoordinator] in
            windowCoordinator?.showChangelogWindow()
        }
        appState.showSupportWindow = { [weak windowCoordinator] in
            windowCoordinator?.showSupportWindow()
        }
        appState.showRecordingControlWindow = { [weak windowCoordinator] in
            windowCoordinator?.showRecordingControlWindow()
        }
        appState.prepareForScreenshotSelection = { [weak windowCoordinator] in
            windowCoordinator?.prepareForScreenshotSelection()
        }
        appState.restoreAfterScreenshotSelection = { [weak windowCoordinator] in
            windowCoordinator?.restoreAfterScreenshotSelection()
        }

        _settingsStore = StateObject(wrappedValue: settingsStore)
        _transcriptStore = StateObject(wrappedValue: transcriptStore)
        _appState = StateObject(wrappedValue: appState)
        self.windowCoordinator = windowCoordinator
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState, transcriptStore: transcriptStore)
        } label: {
            MenuBarLabelView(status: appState.status, elapsedTime: appState.elapsedTimeString)
        }
        .menuBarExtraStyle(.window)
    }
}
