import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    private let appState: AppState
    private let transcriptStore: TranscriptStore
    private let settingsStore: SettingsStore

    private var transcriptWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var aboutWindowController: NSWindowController?
    private var changelogWindowController: NSWindowController?
    private var supportWindowController: NSWindowController?
    private var recordingControlWindowController: NSWindowController?
    private nonisolated(unsafe) var singleInstanceActivationObserver: NSObjectProtocol?
    private var shouldRestoreRecordingControlWindowAfterScreenshotSelection = false

    private let recordingControlSize = NSSize(width: 336, height: 220)
    private let recordingControlAutosaveName = "BugNarratorRecordingControlsWindow"

    init(appState: AppState, transcriptStore: TranscriptStore, settingsStore: SettingsStore) {
        self.appState = appState
        self.transcriptStore = transcriptStore
        self.settingsStore = settingsStore

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

    func showTranscriptWindow() {
        if let transcriptWindowController {
            present(transcriptWindowController)
            return
        }

        let rootView = TranscriptView(appState: appState, transcriptStore: transcriptStore)
        let windowController = NSWindowController(
            window: makeWindow(
                title: "BugNarrator Sessions",
                size: NSSize(width: 1120, height: 720),
                rootView: rootView
            )
        )

        transcriptWindowController = windowController
        present(windowController)
    }

    func showSettingsWindow() {
        if let settingsWindowController {
            present(settingsWindowController)
            return
        }

        let rootView = SettingsView(appState: appState, settingsStore: settingsStore)
        let windowController = NSWindowController(
            window: makeWindow(
                title: "BugNarrator Settings",
                size: NSSize(width: 760, height: 900),
                rootView: rootView
            )
        )

        settingsWindowController = windowController
        present(windowController)
    }

    func showAboutWindow() {
        if let aboutWindowController {
            present(aboutWindowController)
            return
        }

        let rootView = AboutBugNarratorView(appState: appState)
        let windowController = NSWindowController(
            window: makeWindow(
                title: "About BugNarrator",
                size: NSSize(width: 620, height: 720),
                rootView: rootView
            )
        )

        aboutWindowController = windowController
        present(windowController)
    }

    func showChangelogWindow() {
        if let changelogWindowController {
            present(changelogWindowController)
            return
        }

        let rootView = ChangelogView(appState: appState)
        let windowController = NSWindowController(
            window: makeWindow(
                title: "What’s New",
                size: NSSize(width: 760, height: 760),
                rootView: rootView
            )
        )

        changelogWindowController = windowController
        present(windowController)
    }

    func showSupportWindow() {
        if let supportWindowController {
            present(supportWindowController)
            return
        }

        let rootView = SupportView(appState: appState)
        let windowController = NSWindowController(
            window: makeWindow(
                title: "Support BugNarrator",
                size: NSSize(width: 520, height: 460),
                rootView: rootView
            )
        )

        supportWindowController = windowController
        present(windowController)
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

        if let visibleWindowController = [
            transcriptWindowController,
            settingsWindowController,
            aboutWindowController,
            changelogWindowController,
            supportWindowController
        ].compactMap({ $0 }).first(where: { $0.window?.isVisible == true }) {
            present(visibleWindowController)
            return
        }

        if !transcriptStore.sessions.isEmpty || appState.currentTranscript != nil {
            showTranscriptWindow()
        } else {
            showSettingsWindow()
        }
    }

    private func makeRecordingControlWindowController() -> NSWindowController {
        let rootView = RecordingControlPanelView(
            appState: appState,
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
