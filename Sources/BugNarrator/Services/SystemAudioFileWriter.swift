import AudioToolbox
@preconcurrency import AVFoundation
import Foundation

// Thread-safety invariant: every access to the mutable state (`file`,
// `writeError`, `formatInvalidated`) is serialized through `lock`, so this type
// is safe to share across the CoreAudio callback thread and the recording actor
// despite `AVAudioFile` not being Sendable. Hence the `@unchecked` is sound.
final class SystemAudioFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let format: AVAudioFormat
    private var file: AVAudioFile?
    private var writeError: Error?
    private var formatInvalidated = false

    init(fileURL: URL, format: AVAudioFormat) throws {
        self.format = format
        self.file = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
    }

    func write(bufferList: UnsafePointer<AudioBufferList>) {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard let file,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: bufferList, deallocator: nil) else {
            return
        }

        do {
            try file.write(from: buffer)
        } catch {
            writeError = error
        }
    }

    func markFormatInvalidated() {
        lock.lock()
        formatInvalidated = true
        lock.unlock()
    }

    func close() throws {
        lock.lock()
        let writeError = writeError
        let formatInvalidated = formatInvalidated
        file = nil
        self.writeError = nil
        self.formatInvalidated = false
        lock.unlock()

        if formatInvalidated {
            throw AppError.recordingFailure(
                "System audio format changed while recording. Stop and start a new recording after changing output devices or sample rate."
            )
        }

        if let writeError {
            throw AppError.recordingFailure("System audio could not be written. \(writeError.localizedDescription)")
        }
    }
}
