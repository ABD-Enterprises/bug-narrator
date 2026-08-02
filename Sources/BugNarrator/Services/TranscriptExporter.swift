import AppKit
import Foundation
import UniformTypeIdentifiers

enum TranscriptExportFormat {
    case text
    case markdown

    var title: String {
        switch self {
        case .text:
            return "Export TXT"
        case .markdown:
            return "Export Markdown"
        }
    }

    var fileExtension: String {
        switch self {
        case .text:
            return "txt"
        case .markdown:
            return "md"
        }
    }

    var contentType: UTType {
        switch self {
        case .text:
            return .plainText
        case .markdown:
            return UTType(filenameExtension: "md") ?? .plainText
        }
    }
}

/// Records what a session bundle actually contains, including screenshots that
/// were referenced by the session but absent from disk at export time (#914).
/// Mirrors the `manifest.json` idiom already used by `PrivacyDataExporter`.
struct SessionBundleManifest: Encodable {
    let generatedAt: Date
    let sessionID: String
    let exportedFiles: [String]
    let screenshotCount: Int
    let copiedScreenshotCount: Int
    let missingScreenshots: [String]
    let notes: [String]
}

@MainActor
struct TranscriptExporter {
    private let fileManager: FileManager
    private let bundleWriter: AtomicBundleDirectoryWriter
    private let logger = DiagnosticsLogger(category: .export)

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.bundleWriter = AtomicBundleDirectoryWriter(fileManager: fileManager)
    }

    func export(session: TranscriptSession, as format: TranscriptExportFormat) throws -> URL? {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format.contentType]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = session.suggestedFileName(fileExtension: format.fileExtension)

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return nil
        }

        let content: String
        switch format {
        case .text:
            content = session.plainTextContent
        case .markdown:
            content = session.markdownContent
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
        logger.info(
            "transcript_exported",
            "Exported a transcript file.",
            metadata: [
                "session_id": session.id.uuidString,
                "format": format.fileExtension
            ]
        )
        return url
    }

    func exportBundle(session: TranscriptSession) throws -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Export Bundle"
        openPanel.message = "Choose a folder for the exported BugNarrator session bundle."

        guard openPanel.runModal() == .OK, let destinationRoot = openPanel.url else {
            return nil
        }

        return try writeBundle(session: session, to: destinationRoot)
    }

    func writeBundle(session: TranscriptSession, to destinationRoot: URL) throws -> URL {
        // A screenshot file that has been moved or pruned since capture used to
        // make the whole session unexportable. The transcript, summary, and
        // issues are still worth handing to a team, so the export degrades: the
        // present files are copied and the absent ones are named in the
        // manifest instead (#914).
        let missingScreenshots = missingScreenshots(for: session)
        var copiedScreenshotCount = 0
        var exportedFiles = ["transcript.md"]

        let bundleDirectoryURL = try bundleWriter.writeBundle(
            in: destinationRoot,
            suggestedName: session.suggestedBundleDirectoryName
        ) { bundleDirectoryURL in
            try session.markdownContent.write(
                to: bundleDirectoryURL.appendingPathComponent("transcript.md"),
                atomically: true,
                encoding: .utf8
            )

            // `summaryMarkdownContent` renders the review summary and every
            // extracted issue grouped by category — the differentiated output.
            // Sessions that never ran extraction get no file rather than a
            // placeholder saying so.
            if session.issueExtraction != nil {
                try session.summaryMarkdownContent.write(
                    to: bundleDirectoryURL.appendingPathComponent("summary.md"),
                    atomically: true,
                    encoding: .utf8
                )
                exportedFiles.append("summary.md")
            }

            let screenshotsDirectoryURL = bundleDirectoryURL.appendingPathComponent("screenshots", isDirectory: true)
            try fileManager.createDirectory(at: screenshotsDirectoryURL, withIntermediateDirectories: true)

            for screenshot in session.screenshots where fileManager.fileExists(atPath: screenshot.fileURL.path) {
                let destinationURL = uniqueScreenshotDestinationURL(
                    for: screenshot.fileName,
                    in: screenshotsDirectoryURL
                )
                try fileManager.copyItem(at: screenshot.fileURL, to: destinationURL)
                copiedScreenshotCount += 1
            }

            let manifest = SessionBundleManifest(
                generatedAt: Date(),
                sessionID: session.id.uuidString,
                exportedFiles: exportedFiles,
                screenshotCount: session.screenshotCount,
                copiedScreenshotCount: copiedScreenshotCount,
                missingScreenshots: missingScreenshots.map(\.fileName),
                notes: Self.manifestNotes(missingScreenshotCount: missingScreenshots.count)
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(manifest).write(
                to: bundleDirectoryURL.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
        }

        logger.info(
            "session_bundle_exported",
            "Exported a local session bundle.",
            metadata: [
                "session_id": session.id.uuidString,
                "screenshot_count": "\(session.screenshotCount)",
                "copied_screenshot_count": "\(copiedScreenshotCount)",
                "missing_screenshot_count": "\(missingScreenshots.count)"
            ]
        )

        return bundleDirectoryURL
    }

    private static func manifestNotes(missingScreenshotCount: Int) -> [String] {
        var notes = ["This bundle contains the transcript, review output, and captured screenshots for one BugNarrator session."]

        if missingScreenshotCount > 0 {
            notes.append(
                "\(missingScreenshotCount) referenced screenshot file(s) were not found on disk at export time and are listed in missingScreenshots. The rest of the bundle exported normally."
            )
        }

        return notes
    }

    private func missingScreenshots(for session: TranscriptSession) -> [SessionScreenshot] {
        session.screenshots.filter { screenshot in
            !fileManager.fileExists(atPath: screenshot.fileURL.path)
        }
    }

    private func uniqueScreenshotDestinationURL(for fileName: String, in directoryURL: URL) -> URL {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        var candidateURL = directoryURL.appendingPathComponent(fileName)
        var suffix = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            let suffixedName = fileExtension.isEmpty
                ? "\(baseName)-\(suffix)"
                : "\(baseName)-\(suffix).\(fileExtension)"
            candidateURL = directoryURL.appendingPathComponent(suffixedName)
            suffix += 1
        }

        return candidateURL
    }
}
