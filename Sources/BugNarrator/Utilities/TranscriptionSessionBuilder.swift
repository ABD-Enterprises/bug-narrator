import Foundation

enum PostTranscriptionPipelineMode: Equatable {
    case finishedRecording
    case retry

    var savingAction: String {
        switch self {
        case .finishedRecording:
            return "Saving the finished session locally..."
        case .retry:
            return "Saving the recovered session locally..."
        }
    }

    var recordsCompletionTelemetry: Bool {
        self == .finishedRecording
    }
}

enum PostTranscriptionPipelineResult {
    case success(TranscriptSession)
    case persistenceFailure(session: TranscriptSession, error: Error)
    case postTranscriptionFailure(Error)
}

enum TranscriptionSessionBuilder {
    static func completedSession(
        from recordingSession: RecordingSessionDraft,
        recordedAudio: RecordedAudio,
        request: TranscriptionRequest,
        result: TranscriptionResult,
        createdAt: Date = Date()
    ) -> TranscriptSession {
        let sections = TranscriptSectionBuilder.buildSections(
            transcript: result.text,
            segments: result.segments,
            markers: recordingSession.markers,
            duration: recordedAudio.duration
        )

        return TranscriptSession(
            id: recordingSession.sessionID,
            createdAt: createdAt,
            transcript: result.text,
            duration: recordedAudio.duration,
            model: request.model,
            languageHint: request.languageHint,
            prompt: request.prompt,
            markers: recordingSession.markers,
            screenshots: recordingSession.screenshots,
            sections: sections,
            transcriptQualityFindings: result.qualityFindings,
            artifactsDirectoryPath: recordingSession.artifactsDirectoryURL.path
        )
    }

    static func recoveredSession(
        from session: TranscriptSession,
        request: TranscriptionRequest,
        result: TranscriptionResult
    ) -> TranscriptSession {
        let sections = TranscriptSectionBuilder.buildSections(
            transcript: result.text,
            segments: result.segments,
            markers: session.markers,
            duration: session.duration
        )

        return TranscriptSession(
            id: session.id,
            createdAt: session.createdAt,
            transcript: result.text,
            duration: session.duration,
            model: request.model,
            languageHint: request.languageHint,
            prompt: request.prompt,
            markers: session.markers,
            screenshots: session.screenshots,
            sections: sections,
            issueExtraction: nil,
            pendingTranscription: nil,
            transcriptQualityFindings: result.qualityFindings,
            updatedAt: Date(),
            artifactsDirectoryPath: session.artifactsDirectoryPath
        )
    }

    static func retryableSession(
        from recordingSession: RecordingSessionDraft,
        recordedAudio: RecordedAudio,
        request: TranscriptionRequest,
        failureReason: PendingTranscriptionFailureReason,
        preservedAudioURL: URL,
        createdAt: Date = Date(),
        preservedAt: Date = Date()
    ) -> TranscriptSession {
        TranscriptSession(
            id: recordingSession.sessionID,
            createdAt: createdAt,
            transcript: "",
            duration: recordedAudio.duration,
            model: request.model,
            languageHint: request.languageHint,
            prompt: request.prompt,
            markers: recordingSession.markers,
            screenshots: recordingSession.screenshots,
            sections: [],
            issueExtraction: nil,
            pendingTranscription: PendingTranscription(
                audioFileName: preservedAudioURL.lastPathComponent,
                failureReason: failureReason,
                preservedAt: preservedAt
            ),
            updatedAt: createdAt,
            artifactsDirectoryPath: recordingSession.artifactsDirectoryURL.path
        )
    }
}
