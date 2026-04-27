import Foundation

struct RecoveredRecordingImporter: RecoveredRecordingImporting {
    private let fileManager: FileManager
    private let recoveryDirectoryURL: URL
    private let qualityInspector: TranscriptQualityInspector

    init(
        fileManager: FileManager = .default,
        recoveryDirectoryURL: URL = AppSupportLocation.appDirectory()
            .appendingPathComponent("RecoveredRecordings", isDirectory: true),
        qualityInspector: TranscriptQualityInspector = TranscriptQualityInspector()
    ) {
        self.fileManager = fileManager
        self.recoveryDirectoryURL = recoveryDirectoryURL
        self.qualityInspector = qualityInspector
    }

    @MainActor
    func importRecoverableRecordings(
        into transcriptStore: TranscriptStore,
        artifactsService: any SessionArtifactsManaging
    ) throws -> Int {
        guard fileManager.fileExists(atPath: recoveryDirectoryURL.path) else {
            return 0
        }

        let alreadyImported = Set(
            transcriptStore.sessions.compactMap { session in
                session.recoveredSourceFileName ?? session.pendingTranscription?.recoveredSourceFileName
            }
        )

        let audioFiles = try fileManager
            .contentsOfDirectory(
                at: recoveryDirectoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .filter { !alreadyImported.contains($0.lastPathComponent) }
            .sorted {
                modificationDate(for: $0) > modificationDate(for: $1)
            }

        var importedCount = 0
        for audioFileURL in audioFiles {
            let sessionID = UUID()
            let artifactsDirectoryURL = try artifactsService.createArtifactsDirectory(for: sessionID)
            let preservedAudioURL = artifactsService.makeRecordedAudioURL(
                in: artifactsDirectoryURL,
                sourceFileURL: audioFileURL
            )

            if fileManager.fileExists(atPath: preservedAudioURL.path) {
                try fileManager.removeItem(at: preservedAudioURL)
            }
            try fileManager.copyItem(at: audioFileURL, to: preservedAudioURL)

            let transcriptText = recoveredTranscriptText(for: audioFileURL)
            let duration: TimeInterval = 0
            let session: TranscriptSession

            if let transcriptText, !transcriptText.isEmpty {
                let sections = TranscriptSectionBuilder.buildSections(
                    transcript: transcriptText,
                    segments: [],
                    markers: [],
                    duration: duration
                )
                session = TranscriptSession(
                    id: sessionID,
                    createdAt: modificationDate(for: audioFileURL),
                    transcript: transcriptText,
                    duration: duration,
                    model: "recovered",
                    languageHint: nil,
                    prompt: nil,
                    sections: sections,
                    transcriptQualityFindings: qualityInspector.findings(for: transcriptText),
                    recoveredSourceFileName: audioFileURL.lastPathComponent,
                    artifactsDirectoryPath: artifactsDirectoryURL.path
                )
            } else {
                session = TranscriptSession(
                    id: sessionID,
                    createdAt: modificationDate(for: audioFileURL),
                    transcript: "",
                    duration: duration,
                    model: "whisper-1",
                    languageHint: nil,
                    prompt: nil,
                    pendingTranscription: PendingTranscription(
                        audioFileName: preservedAudioURL.lastPathComponent,
                        failureReason: .crashRecovery,
                        preservedAt: Date(),
                        recoveredSourceFileName: audioFileURL.lastPathComponent
                    ),
                    recoveredSourceFileName: audioFileURL.lastPathComponent,
                    artifactsDirectoryPath: artifactsDirectoryURL.path
                )
            }

            try transcriptStore.add(session)
            importedCount += 1
        }

        return importedCount
    }

    private func recoveredTranscriptText(for audioFileURL: URL) -> String? {
        let baseName = audioFileURL.deletingPathExtension().lastPathComponent
        let candidates = [
            recoveryDirectoryURL
                .appendingPathComponent("transcripts", isDirectory: true)
                .appendingPathComponent("\(baseName).transcript.txt"),
            recoveryDirectoryURL
                .appendingPathComponent("transcripts", isDirectory: true)
                .appendingPathComponent("\(baseName).txt")
        ]

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            let text = try? String(contentsOf: candidate, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let text, !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private func modificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? Date()
    }

}
