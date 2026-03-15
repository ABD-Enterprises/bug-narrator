import AppKit
import Combine
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
    private var recordingHUDWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()

    private let recordingHUDSize = NSSize(width: 320, height: 132)
    private let screenshotHideDelayNanoseconds: UInt64 = 250_000_000

    init(appState: AppState, transcriptStore: TranscriptStore, settingsStore: SettingsStore) {
        self.appState = appState
        self.transcriptStore = transcriptStore
        self.settingsStore = settingsStore

        appState.$status
            .map(\.phase)
            .removeDuplicates()
            .sink { [weak self] phase in
                self?.updateRecordingHUD(for: phase)
            }
            .store(in: &cancellables)

        updateRecordingHUD(for: appState.status.phase)
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

    private func present(_ windowController: NSWindowController) {
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateRecordingHUD(for phase: AppStatus.Phase) {
        switch phase {
        case .recording:
            showRecordingHUD()
        case .idle, .success, .error, .transcribing:
            hideRecordingHUD()
        }
    }

    private func showRecordingHUD() {
        if recordingHUDWindowController == nil {
            recordingHUDWindowController = makeRecordingHUDWindowController()
        }

        guard let window = recordingHUDWindowController?.window else {
            return
        }

        positionRecordingHUD(window)
        window.orderFrontRegardless()
    }

    private func hideRecordingHUD() {
        recordingHUDWindowController?.window?.orderOut(nil)
    }

    private func makeRecordingHUDWindowController() -> NSWindowController {
        let rootView = RecordingHUDView(
            appState: appState,
            onInsertMarker: { [weak self] in
                self?.handleRecordingHUDMarker()
            },
            onCaptureScreenshot: { [weak self] in
                self?.handleRecordingHUDScreenshot()
            },
            onStopSession: { [weak self] in
                self?.handleRecordingHUDStop()
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        let panel = RecordingHUDPanel(
            contentRect: NSRect(origin: .zero, size: recordingHUDSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.sharingType = .none

        return NSWindowController(window: panel)
    }

    private func handleRecordingHUDMarker() {
        Task { @MainActor [weak self] in
            await self?.appState.insertMarker()
            self?.restoreRecordingHUDIfNeeded()
        }
    }

    private func handleRecordingHUDScreenshot() {
        hideRecordingHUD()

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(nanoseconds: self.screenshotHideDelayNanoseconds)
            await self.appState.captureScreenshot()
            self.restoreRecordingHUDIfNeeded()
        }
    }

    private func handleRecordingHUDStop() {
        Task { @MainActor [weak self] in
            await self?.appState.stopSession()
            self?.restoreRecordingHUDIfNeeded()
        }
    }

    private func restoreRecordingHUDIfNeeded() {
        guard appState.status.phase == .recording else {
            return
        }

        showRecordingHUD()
    }

    private func positionRecordingHUD(_ window: NSWindow) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: visibleFrame.maxX - recordingHUDSize.width - 24,
            y: visibleFrame.maxY - recordingHUDSize.height - 40
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

private final class RecordingHUDPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
