import Foundation

extension SessionArtifactsManaging {
    /// Copies a finished recording from its temp location into a session artifacts
    /// directory and returns the durable URL, so a successful-but-low-quality
    /// transcript session keeps its audio available for re-transcription (#466).
    /// The source is left untouched; the caller decides when to delete the temp.
    func preserveRecordedAudio(_ recordedAudio: RecordedAudio, in directoryURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let destinationURL = makeRecordedAudioURL(in: directoryURL, sourceFileURL: recordedAudio.fileURL)

        if recordedAudio.fileURL.standardizedFileURL != destinationURL.standardizedFileURL {
            if !fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: recordedAudio.fileURL, to: destinationURL)
        }

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 0 else {
            try? fileManager.removeItem(at: destinationURL)
            throw AppError.recordingFailure("The preserved audio file was empty.")
        }

        return destinationURL
    }
}
