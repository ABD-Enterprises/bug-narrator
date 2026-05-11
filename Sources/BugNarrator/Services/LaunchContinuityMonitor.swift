import Foundation

struct UncleanExitObservation: Equatable {
    let previousLaunchStartedAt: Date
    let detectedAt: Date
}

struct LaunchContinuityMonitor {
    private let fileManager: FileManager
    private let stateURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, stateURL: URL? = nil) {
        self.fileManager = fileManager
        self.stateURL = stateURL ?? AppSupportLocation.appDirectory(fileManager: fileManager)
            .appendingPathComponent("launch-state.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    func beginLaunch(now: Date = Date()) -> UncleanExitObservation? {
        let previousState = loadState()
        persist(LaunchState(startedAt: now))

        guard let previousState else {
            return nil
        }

        return UncleanExitObservation(
            previousLaunchStartedAt: previousState.startedAt,
            detectedAt: now
        )
    }

    func markGracefulTermination() {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return
        }

        try? fileManager.removeItem(at: stateURL)
    }

    private func loadState() -> LaunchState? {
        guard fileManager.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL) else {
            return nil
        }

        return try? decoder.decode(LaunchState.self, from: data)
    }

    private func persist(_ state: LaunchState) {
        let parentDirectoryURL = stateURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDirectoryURL.path) {
            try? fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
        }

        guard let data = try? encoder.encode(state) else {
            return
        }

        try? data.write(to: stateURL, options: [.atomic])
    }
}

private struct LaunchState: Codable {
    let startedAt: Date
}
