import Darwin
import SwiftUI

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    static var appState: AppState?
    @MainActor
    static var launchContinuityMonitor: LaunchContinuityMonitor?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.appState?.applicationShouldTerminate() ?? .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.launchContinuityMonitor?.markGracefulTermination()
    }
}

private struct WindowSceneRegistrar: View {
    @ObservedObject var appState: AppState
    let windowCoordinator: WindowCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear {
                windowCoordinator.configureSceneActions(
                    showTranscript: { openWindow(id: WindowCoordinator.SceneID.transcript) },
                    showSettings: { openWindow(id: WindowCoordinator.SceneID.settings) },
                    showAbout: { openWindow(id: WindowCoordinator.SceneID.about) },
                    showChangelog: { openWindow(id: WindowCoordinator.SceneID.changelog) },
                    showSupport: { openWindow(id: WindowCoordinator.SceneID.support) }
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
            }
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
        let telemetryStorageURL = bootstrap.isolatedStorageRootURL?
            .appendingPathComponent("operational-telemetry.jsonl")
        let launchStateURL = bootstrap.isolatedStorageRootURL?
            .appendingPathComponent("launch-state.json")
        let telemetryRecorder = OperationalTelemetryRecorder(storageURL: telemetryStorageURL)
        let launchContinuityMonitor = LaunchContinuityMonitor(stateURL: launchStateURL)

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
        AppLifecycleDelegate.launchContinuityMonitor = launchContinuityMonitor
        self.windowCoordinator = windowCoordinator

        if let observation = launchContinuityMonitor.beginLaunch() {
            let timestampFormatter = BugNarratorDiagnostics.makeTimestampFormatter()
            let metadata = [
                "previous_launch_started_at": timestampFormatter.string(from: observation.previousLaunchStartedAt),
                "detected_at": timestampFormatter.string(from: observation.detectedAt)
            ]
            DiagnosticsLogger(category: .settings).warning(
                "unclean_exit_detected",
                "BugNarrator detected that the previous launch did not terminate cleanly.",
                metadata: metadata
            )
            telemetryRecorder.record("unclean_exit_detected", metadata: metadata)
        }

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
            MenuBarView(
                appState: appState,
                recordingTimer: appState.recordingTimer,
                transcriptStore: transcriptStore
            )
            .background(WindowSceneRegistrar(appState: appState, windowCoordinator: windowCoordinator))
        } label: {
            MenuBarLabelView(
                status: appState.status,
                recordingTimer: appState.recordingTimer
            )
            .background(WindowSceneRegistrar(appState: appState, windowCoordinator: windowCoordinator))
        }
        .menuBarExtraStyle(.window)

        Window("BugNarrator Sessions", id: WindowCoordinator.SceneID.transcript) {
            TranscriptView(
                appState: appState,
                recordingTimer: appState.recordingTimer,
                transcriptStore: transcriptStore
            )
        }
        .defaultSize(width: 1120, height: 720)

        Window("BugNarrator Settings", id: WindowCoordinator.SceneID.settings) {
            SettingsView(appState: appState, settingsStore: settingsStore)
        }
        .defaultSize(width: 760, height: 900)

        Window("About BugNarrator", id: WindowCoordinator.SceneID.about) {
            AboutBugNarratorView(appState: appState)
        }
        .defaultSize(width: 620, height: 720)

        Window("What’s New", id: WindowCoordinator.SceneID.changelog) {
            ChangelogView(appState: appState)
        }
        .defaultSize(width: 760, height: 760)

        Window("Support BugNarrator", id: WindowCoordinator.SceneID.support) {
            SupportView(appState: appState)
        }
        .defaultSize(width: 520, height: 460)
    }
}
