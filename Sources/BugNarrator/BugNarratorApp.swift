import Darwin
import SwiftUI

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    static var appState: AppState?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.appState?.applicationShouldTerminate() ?? .terminateNow
    }
}

@main
struct BugNarratorApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var transcriptStore: TranscriptStore
    @StateObject private var appState: AppState

    private let windowCoordinator: WindowCoordinator

    init() {
        let runtimeEnvironment = AppRuntimeEnvironment()
        let bootstrap = AppBootstrap(runtimeEnvironment: runtimeEnvironment)

        if !runtimeEnvironment.shouldBypassSingleInstanceEnforcement {
            guard SingleInstanceController.enforcePrimaryInstance() else {
                exit(EXIT_SUCCESS)
            }
        }

        let settingsStore = bootstrap.settingsStore
        let transcriptStore = bootstrap.transcriptStore
        #if DEBUG
        UITestRuntimeSupport.seedIfNeeded(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            runtimeEnvironment: runtimeEnvironment,
            storageRootURL: bootstrap.isolatedStorageRootURL
        )
        #endif

        let appState: AppState
        #if DEBUG
        if runtimeEnvironment.shouldUseDeterministicUITestServices {
            appState = UITestRuntimeSupport.makeAppState(
                settingsStore: settingsStore,
                transcriptStore: transcriptStore,
                runtimeEnvironment: runtimeEnvironment,
                storageRootURL: bootstrap.isolatedStorageRootURL
            )
        } else {
            appState = AppState(
                settingsStore: settingsStore,
                transcriptStore: transcriptStore,
                runtimeEnvironment: runtimeEnvironment
            )
        }
        #else
        appState = AppState(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            runtimeEnvironment: runtimeEnvironment
        )
        #endif
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
        AppLifecycleDelegate.appState = appState
        self.windowCoordinator = windowCoordinator

        if runtimeEnvironment.shouldOpenSettingsOnLaunch {
            DispatchQueue.main.async {
                windowCoordinator.showSettingsWindow()
            }
        }

        if runtimeEnvironment.shouldOpenSessionLibraryOnLaunch {
            DispatchQueue.main.async {
                windowCoordinator.showTranscriptWindow()
            }
        }

        if runtimeEnvironment.shouldOpenRecordingControlsOnLaunch {
            DispatchQueue.main.async {
                windowCoordinator.showRecordingControlWindow()
            }
        }
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
