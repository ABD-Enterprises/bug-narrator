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

@MainActor
struct TranscriptExporter {
    private let fileManager: FileManager
    private let bundleWriter: AtomicBundleDirectoryWriter
    private let logger = DiagnosticsLogger(category: .export)

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.bundleWriter = AtomicBundleDirectoryWriter(fileManager: fileManager)
    }

    func export(session: TranscriptSession, as format: TranscriptExportFormat) throws {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format.contentType]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = session.suggestedFileName(fileExtension: format.fileExtension)

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
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
    }

    func exportBundle(session: TranscriptSession) throws {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Export Bundle"
        openPanel.message = "Choose a folder for the exported BugNarrator session bundle."

        guard openPanel.runModal() == .OK, let destinationRoot = openPanel.url else {
            return
        }

        _ = try writeBundle(session: session, to: destinationRoot)
    }

    func writeBundle(session: TranscriptSession, to destinationRoot: URL) throws -> URL {
        let missingScreenshots = missingScreenshots(for: session)
        if !missingScreenshots.isEmpty {
            let missingList = missingScreenshots.map(\.fileName).joined(separator: ", ")
            throw AppError.exportFailure(
                "This session bundle is missing referenced screenshot files: \(missingList). Recreate the screenshots or remove the stale references before exporting."
            )
        }

        var copiedScreenshotCount = 0

        let bundleDirectoryURL = try bundleWriter.writeBundle(
            in: destinationRoot,
            suggestedName: session.suggestedBundleDirectoryName
        ) { bundleDirectoryURL in
            try session.markdownContent.write(
                to: bundleDirectoryURL.appendingPathComponent("transcript.md"),
                atomically: true,
                encoding: .utf8
            )

            let screenshotsDirectoryURL = bundleDirectoryURL.appendingPathComponent("screenshots", isDirectory: true)
            try fileManager.createDirectory(at: screenshotsDirectoryURL, withIntermediateDirectories: true)

            for screenshot in session.screenshots {
                let destinationURL = uniqueScreenshotDestinationURL(
                    for: screenshot.fileName,
                    in: screenshotsDirectoryURL
                )
                try fileManager.copyItem(at: screenshot.fileURL, to: destinationURL)
                copiedScreenshotCount += 1
            }
        }

        logger.info(
            "session_bundle_exported",
            "Exported a local session bundle.",
            metadata: [
                "session_id": session.id.uuidString,
                "screenshot_count": "\(session.screenshotCount)",
                "copied_screenshot_count": "\(copiedScreenshotCount)",
                "missing_screenshot_count": "0"
            ]
        )

        return bundleDirectoryURL
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
