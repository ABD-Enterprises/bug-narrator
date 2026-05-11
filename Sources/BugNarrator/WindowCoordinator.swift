import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    enum SceneID {
        static let transcript = "transcript"
        static let settings = "settings"
        static let about = "about"
        static let changelog = "changelog"
        static let support = "support"
    }

    private let appState: AppState
    private let transcriptStore: TranscriptStore

    private var recordingControlWindowController: NSWindowController?
    private nonisolated(unsafe) var singleInstanceActivationObserver: NSObjectProtocol?
    private var shouldRestoreRecordingControlWindowAfterScreenshotSelection = false
    private var pendingSceneIDs: Set<String> = []
    private var showTranscriptSceneAction: (() -> Void)?
    private var showSettingsSceneAction: (() -> Void)?
    private var showAboutSceneAction: (() -> Void)?
    private var showChangelogSceneAction: (() -> Void)?
    private var showSupportSceneAction: (() -> Void)?

    private let recordingControlSize = NSSize(width: 336, height: 220)
    private let recordingControlAutosaveName = "BugNarratorRecordingControlsWindow"

    init(appState: AppState, transcriptStore: TranscriptStore, settingsStore _: SettingsStore) {
        self.appState = appState
        self.transcriptStore = transcriptStore

        singleInstanceActivationObserver = DistributedNotificationCenter.default().addObserver(
            forName: SingleInstanceController.activationNotificationName,
            object: Bundle.main.bundleIdentifier,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.presentPrimaryInterfaceForReactivation()
            }
        }
    }

    deinit {
        if let singleInstanceActivationObserver {
            DistributedNotificationCenter.default().removeObserver(singleInstanceActivationObserver)
        }
    }

    func configureSceneActions(
        showTranscript: @escaping () -> Void,
        showSettings: @escaping () -> Void,
        showAbout: @escaping () -> Void,
        showChangelog: @escaping () -> Void,
        showSupport: @escaping () -> Void
    ) {
        showTranscriptSceneAction = showTranscript
        showSettingsSceneAction = showSettings
        showAboutSceneAction = showAbout
        showChangelogSceneAction = showChangelog
        showSupportSceneAction = showSupport

        let pendingSceneIDs = self.pendingSceneIDs
        self.pendingSceneIDs.removeAll()
        for sceneID in pendingSceneIDs {
            openScene(id: sceneID)
        }
    }

    func showTranscriptWindow() {
        openScene(id: SceneID.transcript)
    }

    func showSettingsWindow() {
        openScene(id: SceneID.settings)
    }

    func showAboutWindow() {
        openScene(id: SceneID.about)
    }

    func showChangelogWindow() {
        openScene(id: SceneID.changelog)
    }

    func showSupportWindow() {
        openScene(id: SceneID.support)
    }

    func showRecordingControlWindow() {
        if recordingControlWindowController == nil {
            recordingControlWindowController = makeRecordingControlWindowController()
        }

        present(recordingControlWindowController!)
    }

    private func present(_ windowController: NSWindowController) {
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentPrimaryInterfaceForReactivation() {
        if let recordingControlWindowController,
           let window = recordingControlWindowController.window,
           window.isVisible {
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if !transcriptStore.libraryEntries.isEmpty || appState.currentTranscript != nil {
            showTranscriptWindow()
        } else {
            showSettingsWindow()
        }
    }

    private func makeRecordingControlWindowController() -> NSWindowController {
        let rootView = RecordingControlPanelView(
            appState: appState,
            recordingTimer: appState.recordingTimer,
            onStartSession: { [weak self] in
                self?.handleRecordingControlStart()
            },
            onStopSession: { [weak self] in
                self?.handleRecordingControlStop()
            },
            onCaptureScreenshot: { [weak self] in
                self?.handleRecordingControlScreenshot()
            },
            onClose: { [weak self] in
                self?.recordingControlWindowController?.window?.performClose(nil)
            }
        )
        let panel = makeWindow(
            title: "BugNarrator Controls",
            size: recordingControlSize,
            rootView: rootView
        )

        panel.styleMask.remove(.resizable)
        panel.styleMask.remove(.miniaturizable)
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.setFrameAutosaveName(recordingControlAutosaveName)

        return NSWindowController(window: panel)
    }

    private func handleRecordingControlStart() {
        Task { @MainActor [weak self] in
            await self?.appState.startSession()
        }
    }

    private func handleRecordingControlStop() {
        Task { @MainActor [weak self] in
            await self?.appState.stopSession()
        }
    }

    private func handleRecordingControlScreenshot() {
        Task { @MainActor [weak self] in
            await self?.appState.captureScreenshot()
        }
    }

    func prepareForScreenshotSelection() {
        guard let window = recordingControlWindowController?.window else {
            shouldRestoreRecordingControlWindowAfterScreenshotSelection = false
            return
        }

        shouldRestoreRecordingControlWindowAfterScreenshotSelection = window.isVisible
        if shouldRestoreRecordingControlWindowAfterScreenshotSelection {
            window.orderOut(nil)
        }
    }

    func restoreAfterScreenshotSelection() {
        guard shouldRestoreRecordingControlWindowAfterScreenshotSelection,
              let window = recordingControlWindowController?.window else {
            shouldRestoreRecordingControlWindowAfterScreenshotSelection = false
            return
        }

        shouldRestoreRecordingControlWindowAfterScreenshotSelection = false
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openScene(id: String) {
        let action: (() -> Void)? = switch id {
        case SceneID.transcript:
            showTranscriptSceneAction
        case SceneID.settings:
            showSettingsSceneAction
        case SceneID.about:
            showAboutSceneAction
        case SceneID.changelog:
            showChangelogSceneAction
        case SceneID.support:
            showSupportSceneAction
        default:
            nil
        }

        guard let action else {
            pendingSceneIDs.insert(id)
            return
        }

        action()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, rootView: Content) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.center()

        return window
    }
}
