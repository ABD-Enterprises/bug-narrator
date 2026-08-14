import AVFoundation
import Darwin
import SwiftUI
private struct WindowSceneRegistrar: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var transcriptStore: TranscriptStore
    let windowCoordinator: WindowCoordinator
    /// True under an isolated test runtime. UI tests launch straight into a
    /// specific window, so an automatic welcome or changelog window would cover
    /// the surface under test.
    let suppressesAutomaticLaunchWindows: Bool
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
                    showSupport: { openWindow(id: WindowCoordinator.SceneID.support) },
                    showWelcome: { openWindow(id: WindowCoordinator.SceneID.welcome) }
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

                presentLaunchWindowIfNeeded()
            }
    }

    /// Opens at most one window unprompted on launch: the first-run tour
    /// (#357) or the What's New sheet (#386), never both.
    ///
    /// An earlier version called each independently and argued they could not
    /// overlap. `OnboardingFlow.launchPresentation` records the case that broke
    /// that argument; the precedence is now explicit rather than emergent.
    ///
    /// The onboarding flag is stamped here, at presentation, rather than on the
    /// tour's Done button, so every exit path counts as shown — including the
    /// window's close box, and the second registrar (this view is attached to
    /// both the MenuBarExtra content and its label, so `onAppear` runs twice
    /// per launch and would otherwise reopen the tour the user just closed).
    private func presentLaunchWindowIfNeeded() {
        guard !suppressesAutomaticLaunchWindows else { return }

        let presentation = OnboardingFlow.launchPresentation(
            shouldPresentWelcome: shouldPresentWelcome,
            shouldAutoShowChangelog: appState.shouldAutoShowChangelogOnLaunch()
        )

        switch presentation {
        case .welcome:
            settingsStore.markFirstRunOnboardingCompleted()
            windowCoordinator.showWelcomeWindow()
        case .changelog:
            appState.presentChangelogIfNeeded()
        case .none:
            break
        }
    }

    private var shouldPresentWelcome: Bool {
        return OnboardingFlow.shouldPresentOnLaunch(
            hasCompletedFirstRunOnboarding: settingsStore.hasCompletedFirstRunOnboarding,
            hasExistingUserState: !transcriptStore.libraryEntries.isEmpty,
            snapshot: OnboardingSnapshot(
                hasUsableAIProviderCredential: settingsStore.hasUsableAIProviderCredential,
                providerConfigurationIsCompatible: settingsStore.aiProviderCompatibilityIssue == nil,
                microphoneAuthorized: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                hasAnyCaptureHotkeyAssigned: settingsStore.hasAnyCaptureHotkeyAssigned
            )
        )
    }
}

@main
struct BugNarratorApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var transcriptStore: TranscriptStore
    @StateObject private var appState: AppState

    private let windowCoordinator: WindowCoordinator
    private let suppressesAutomaticLaunchWindows: Bool

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
        self.suppressesAutomaticLaunchWindows = runtimeEnvironment.usesIsolatedRuntime

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
            .background(
                WindowSceneRegistrar(
                    appState: appState,
                    settingsStore: settingsStore,
                    transcriptStore: transcriptStore,
                    windowCoordinator: windowCoordinator,
                    suppressesAutomaticLaunchWindows: suppressesAutomaticLaunchWindows
                )
            )
        } label: {
            MenuBarLabelView(
                status: appState.status,
                recordingTimer: appState.recordingTimer
            )
            .background(
                WindowSceneRegistrar(
                    appState: appState,
                    settingsStore: settingsStore,
                    transcriptStore: transcriptStore,
                    windowCoordinator: windowCoordinator,
                    suppressesAutomaticLaunchWindows: suppressesAutomaticLaunchWindows
                )
            )
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Show Welcome Tour") {
                    windowCoordinator.showWelcomeWindow()
                }
                Button("BugNarrator User Guide") {
                    NSWorkspace.shared.open(BugNarratorLinks.documentation)
                }
                Button("Report a Bug") {
                    NSWorkspace.shared.open(BugNarratorLinks.issues)
                }
                Button("Visit Repository") {
                    NSWorkspace.shared.open(BugNarratorLinks.repository)
                }
            }
        }

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

        Window("Welcome to BugNarrator", id: WindowCoordinator.SceneID.welcome) {
            WelcomeView(appState: appState, settingsStore: settingsStore)
        }
        .defaultSize(width: 560, height: 520)

        Window("Support BugNarrator", id: WindowCoordinator.SceneID.support) {
            SupportView(appState: appState)
        }
        .defaultSize(width: 520, height: 460)
    }
}
