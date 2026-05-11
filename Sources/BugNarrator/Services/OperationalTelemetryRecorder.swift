import Foundation

struct OperationalTelemetryEvent: Codable, Equatable {
    let timestamp: Date
    let name: String
    let metadata: [String: String]

    init(timestamp: Date = Date(), name: String, metadata: [String: String] = [:]) {
        self.timestamp = timestamp
        self.name = name
        self.metadata = metadata
    }
}

struct OperationalTelemetryRecorder {
    private let fileManager: FileManager
    private let storageURL: URL
    private let encoder = JSONEncoder()

    init(fileManager: FileManager = .default, storageURL: URL? = nil) {
        self.fileManager = fileManager
        self.storageURL = storageURL ?? AppSupportLocation.appDirectory(fileManager: fileManager)
            .appendingPathComponent("operational-telemetry.jsonl")
        encoder.dateEncodingStrategy = .iso8601
    }

    func record(_ name: String, metadata: [String: String] = [:]) {
        do {
            let parentDirectoryURL = storageURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parentDirectoryURL.path) {
                try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
            }

            let event = OperationalTelemetryEvent(name: name, metadata: metadata)
            var line = try encoder.encode(event)
            line.append(0x0A)

            if fileManager.fileExists(atPath: storageURL.path) {
                let handle = try FileHandle(forWritingTo: storageURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: storageURL, options: [.atomic])
            }
        } catch {
            DiagnosticsLogger(category: .settings).warning(
                "operational_telemetry_write_failed",
                "BugNarrator could not write a local telemetry event.",
                metadata: ["event": name]
            )
        }
    }
}
