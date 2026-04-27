import Foundation

struct AudioUploadPolicy {
    static let maximumSingleUploadBytes = 24 * 1_024 * 1_024
    static let warningDuration: TimeInterval = 30 * 60

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func validate(fileURL: URL) throws -> AudioFileInspection {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw AppError.transcriptionFailure("The recorded audio file could not be found.")
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0

        guard fileSize > 0 else {
            throw AppError.transcriptionFailure("The recorded audio file was empty.")
        }

        guard fileSize <= Self.maximumSingleUploadBytes else {
            let size = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
            let limit = ByteCountFormatter.string(fromByteCount: Int64(Self.maximumSingleUploadBytes), countStyle: .file)
            throw AppError.transcriptionFailure(
                "The recorded audio chunk is \(size), which is larger than BugNarrator's \(limit) safe upload limit. Shorten the recording or use a lower-bitrate source."
            )
        }

        return AudioFileInspection(
            fileSizeBytes: fileSize,
            duration: nil
        )
    }
}

struct AudioFileInspection: Equatable {
    let fileSizeBytes: Int
    let duration: TimeInterval?

    var exceedsLongRecordingWarningThreshold: Bool {
        guard let duration else {
            return false
        }

        return duration >= AudioUploadPolicy.warningDuration
    }
}
