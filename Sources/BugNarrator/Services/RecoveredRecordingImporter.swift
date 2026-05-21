import Foundation

struct RecoveredRecordingImporter: RecoveredRecordingImporting {
    private static let supportedAudioExtensions: Set<String> = ["m4a", "wav"]

    private let fileManager: FileManager
    private let recoveryDirectoryURL: URL
    private let qualityInspector: TranscriptQualityInspector
    private let logger: DiagnosticsLogger

    init(
        fileManager: FileManager = .default,
        recoveryDirectoryURL: URL = AppSupportLocation.appDirectory()
            .appendingPathComponent("RecoveredRecordings", isDirectory: true),
        qualityInspector: TranscriptQualityInspector = TranscriptQualityInspector(),
        logger: DiagnosticsLogger = DiagnosticsLogger(category: .sessionLibrary)
    ) {
        self.fileManager = fileManager
        self.recoveryDirectoryURL = recoveryDirectoryURL
        self.qualityInspector = qualityInspector
        self.logger = logger
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
            transcriptStore.libraryEntries.compactMap(\.recoveredSourceFileName)
        )

        let audioFiles = try fileManager
            .contentsOfDirectory(
                at: recoveryDirectoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter(Self.isImportableAudioFile)
            .filter { !alreadyImported.contains($0.lastPathComponent) }
            .sorted {
                modificationDate(for: $0) > modificationDate(for: $1)
            }

        var importedCount = 0
        for audioFileURL in audioFiles {
            let sessionID = UUID()
            do {
                let artifactsDirectoryURL = try artifactsService.createArtifactsDirectory(for: sessionID)
                do {
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
                } catch {
                    try? fileManager.removeItem(at: artifactsDirectoryURL)
                    logger.error(
                        "recovered_recording_import_skipped",
                        "A recovered recording could not be imported and was skipped.",
                        metadata: [
                            "source_file_name": audioFileURL.lastPathComponent,
                            "session_id": sessionID.uuidString,
                            "underlying_error": error.localizedDescription
                        ]
                    )
                }
            } catch {
                logger.error(
                    "recovered_recording_artifacts_directory_failed",
                    "A recovered recording artifacts directory could not be created and the file was skipped.",
                    metadata: [
                        "source_file_name": audioFileURL.lastPathComponent,
                        "session_id": sessionID.uuidString,
                        "underlying_error": error.localizedDescription
                    ]
                )
            }
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

    private static func isRecoverableAudioFile(_ url: URL) -> Bool {
        supportedAudioExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isImportableAudioFile(_ url: URL) -> Bool {
        isRecoverableAudioFile(url) && isRegularFile(url) && fileSize(for: url) > 0
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true
    }

    private static func fileSize(for url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private func modificationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? Date()
    }

}
