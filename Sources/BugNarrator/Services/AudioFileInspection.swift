import Foundation

struct AudioFileInspection: Equatable {
    let fileSizeBytes: Int64
    let duration: TimeInterval?

    var exceedsLongRecordingWarningThreshold: Bool {
        guard let duration else {
            return false
        }

        return duration >= AudioUploadPolicy.warningDuration
    }
}
