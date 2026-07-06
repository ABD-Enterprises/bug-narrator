import Foundation

struct DebugSessionMetadata: Codable, Equatable {
    enum Source: String, Codable {
        case activeRecording
        case transcript
        case none
    }

    let source: Source
    let sessionID: UUID?
    let statusTitle: String
    let statusDetail: String?
    let errorMessage: String?
    let createdAt: Date?
    let updatedAt: Date?
    let duration: TimeInterval?
    let transcriptCharacterCount: Int?
    let sectionsCount: Int
    let markerCount: Int
    let screenshotCount: Int
    let issueCount: Int
    let summaryCharacterCount: Int?
    let artifactsDirectoryExists: Bool
    let missingScreenshotFiles: [String]

    static func make(
        currentTranscript: TranscriptSession?,
        displayedTranscript: TranscriptSession?,
        activeRecordingSession: RecordingSessionDraft?,
        status: AppStatus,
        currentError: AppError?
    ) -> DebugSessionMetadata {
        if let activeRecordingSession {
            return DebugSessionMetadata(
                source: .activeRecording,
                sessionID: activeRecordingSession.sessionID,
                statusTitle: status.title,
                statusDetail: status.detail,
                errorMessage: currentError?.userMessage,
                createdAt: nil,
                updatedAt: nil,
                duration: nil,
                transcriptCharacterCount: nil,
                sectionsCount: 0,
                markerCount: activeRecordingSession.markers.count,
                screenshotCount: activeRecordingSession.screenshots.count,
                issueCount: 0,
                summaryCharacterCount: nil,
                artifactsDirectoryExists: FileManager.default.fileExists(
                    atPath: activeRecordingSession.artifactsDirectoryURL.path
                ),
                missingScreenshotFiles: activeRecordingSession.screenshots.compactMap { screenshot in
                    FileManager.default.fileExists(atPath: screenshot.fileURL.path) ? nil : screenshot.fileName
                }
            )
        }

        if let session = displayedTranscript ?? currentTranscript {
            let missingScreenshotFiles = session.screenshots.compactMap { screenshot in
                FileManager.default.fileExists(atPath: screenshot.fileURL.path) ? nil : screenshot.fileName
            }

            return DebugSessionMetadata(
                source: .transcript,
                sessionID: session.id,
                statusTitle: status.title,
                statusDetail: status.detail,
                errorMessage: currentError?.userMessage,
                createdAt: session.createdAt,
                updatedAt: session.updatedAt,
                duration: session.duration,
                transcriptCharacterCount: session.transcript.count,
                sectionsCount: session.sections.count,
                markerCount: session.markerCount,
                screenshotCount: session.screenshotCount,
                issueCount: session.issueCount,
                summaryCharacterCount: session.summaryText.count,
                artifactsDirectoryExists: session.artifactsDirectoryURL.map {
                    FileManager.default.fileExists(atPath: $0.path)
                } ?? false,
                missingScreenshotFiles: missingScreenshotFiles
            )
        }

        return DebugSessionMetadata(
            source: .none,
            sessionID: nil,
            statusTitle: status.title,
            statusDetail: status.detail,
            errorMessage: currentError?.userMessage,
            createdAt: nil,
            updatedAt: nil,
            duration: nil,
            transcriptCharacterCount: nil,
            sectionsCount: 0,
            markerCount: 0,
            screenshotCount: 0,
            issueCount: 0,
            summaryCharacterCount: nil,
            artifactsDirectoryExists: false,
            missingScreenshotFiles: []
        )
    }
}

