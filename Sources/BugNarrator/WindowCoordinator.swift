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
    private var singleInstanceActivationObserver: NSObjectProtocol?

    private let recordingControlSize = NSSize(width: 360, height: 244)
    private let screenshotHideDelayNanoseconds: UInt64 = 250_000_000

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

        guard let window = recordingControlWindowController?.window else {
            return
        }

        positionRecordingControlWindow(window)
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
            positionRecordingControlWindow(window)
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
            onInsertMarker: { [weak self] in
                self?.handleRecordingControlMarker()
            },
            onCaptureScreenshot: { [weak self] in
                self?.handleRecordingControlScreenshot()
            },
            onClose: { [weak self] in
                self?.recordingControlWindowController?.window?.performClose(nil)
            }
        )
        let panel = makeWindow(
            title: "Recording Controls",
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

        return NSWindowController(window: panel)
    }

    private func handleRecordingControlStart() {
        Task { @MainActor [weak self] in
            self?.showRecordingControlWindow()
            await self?.appState.startSession()
        }
    }

    private func handleRecordingControlStop() {
        Task { @MainActor [weak self] in
            await self?.appState.stopSession()
        }
    }

    private func handleRecordingControlMarker() {
        Task { @MainActor [weak self] in
            await self?.appState.insertMarker()
        }
    }

    private func handleRecordingControlScreenshot() {
        recordingControlWindowController?.window?.orderOut(nil)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(nanoseconds: self.screenshotHideDelayNanoseconds)
            await self.appState.captureScreenshot()

            guard let window = self.recordingControlWindowController?.window, window.isVisible == false else {
                return
            }

            self.positionRecordingControlWindow(window)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func positionRecordingControlWindow(_ window: NSWindow) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: visibleFrame.maxX - recordingControlSize.width - 28,
            y: visibleFrame.maxY - recordingControlSize.height - 54
        )
        window.setFrameOrigin(origin)
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
