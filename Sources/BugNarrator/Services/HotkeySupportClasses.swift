import Combine
import Foundation

@MainActor
final class HotkeySettingsBinder {
    private let hotkeyManager: any HotkeyManaging
    private var cancellables = Set<AnyCancellable>()

    init(hotkeyManager: any HotkeyManaging) {
        self.hotkeyManager = hotkeyManager
    }

    func bind(settingsStore: SettingsStore) {
        cancellables.removeAll()

        settingsStore.$startRecordingHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .startRecording)
            }
            .store(in: &cancellables)

        settingsStore.$stopRecordingHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .stopRecording)
            }
            .store(in: &cancellables)

        settingsStore.$screenshotHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .captureScreenshot)
            }
            .store(in: &cancellables)

        register(assignments: settingsStore.hotkeyAssignments)
    }

    private func register(assignments: [(action: HotkeyAction, shortcut: HotkeyShortcut)]) {
        for assignment in assignments {
            hotkeyManager.register(shortcut: assignment.shortcut, for: assignment.action)
        }
    }
}

@MainActor
final class HotkeyActionDispatcher {
    private let statusPhase: () -> AppStatus.Phase
    private let startRecording: () async -> Void
    private let stopRecording: () async -> Void
    private let captureScreenshot: () async -> Void

    init(
        statusPhase: @escaping () -> AppStatus.Phase,
        startRecording: @escaping () async -> Void,
        stopRecording: @escaping () async -> Void,
        captureScreenshot: @escaping () async -> Void
    ) {
        self.statusPhase = statusPhase
        self.startRecording = startRecording
        self.stopRecording = stopRecording
        self.captureScreenshot = captureScreenshot
    }

    func handle(_ action: HotkeyAction) {
        switch action {
        case .startRecording:
            Task {
                await startRecording()
            }
        case .stopRecording:
            guard statusPhase() == .recording else {
                return
            }
            Task {
                await stopRecording()
            }
        case .captureScreenshot:
            Task {
                await captureScreenshot()
            }
        }
    }
}
