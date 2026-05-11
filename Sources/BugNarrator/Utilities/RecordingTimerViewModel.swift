import Foundation

@MainActor
final class RecordingTimerViewModel: ObservableObject {
    @Published private(set) var elapsedDuration: TimeInterval = 0

    private var timerTask: Task<Void, Never>?

    var elapsedTimeString: String {
        ElapsedTimeFormatter.string(from: elapsedDuration)
    }

    func start() {
        timerTask?.cancel()
        elapsedDuration = 0
        let startDate = Date()

        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.elapsedDuration = Date().timeIntervalSince(startDate)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop(resetElapsed: Bool) {
        timerTask?.cancel()
        timerTask = nil

        if resetElapsed {
            elapsedDuration = 0
        }
    }
}
