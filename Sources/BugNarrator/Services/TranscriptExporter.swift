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
    private let fileManager = FileManager.default
    private let logger = DiagnosticsLogger(category: .export)

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

        let bundleDirectoryURL = uniqueBundleDirectoryURL(
            baseDirectory: destinationRoot,
            suggestedName: session.suggestedBundleDirectoryName
        )

        try fileManager.createDirectory(at: bundleDirectoryURL, withIntermediateDirectories: true)
        try session.plainTextContent.write(
            to: bundleDirectoryURL.appendingPathComponent("transcript.txt"),
            atomically: true,
            encoding: .utf8
        )
        try session.markdownContent.write(
            to: bundleDirectoryURL.appendingPathComponent("transcript.md"),
            atomically: true,
            encoding: .utf8
        )
        try session.summaryMarkdownContent.write(
            to: bundleDirectoryURL.appendingPathComponent("summary.md"),
            atomically: true,
            encoding: .utf8
        )

        let screenshotsDirectoryURL = bundleDirectoryURL.appendingPathComponent("screenshots", isDirectory: true)
        try fileManager.createDirectory(at: screenshotsDirectoryURL, withIntermediateDirectories: true)

        for screenshot in session.screenshots where fileManager.fileExists(atPath: screenshot.fileURL.path) {
            let destinationURL = screenshotsDirectoryURL.appendingPathComponent(screenshot.fileName)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: screenshot.fileURL, to: destinationURL)
        }

        logger.info(
            "session_bundle_exported",
            "Exported a local session bundle.",
            metadata: [
                "session_id": session.id.uuidString,
                "screenshot_count": "\(session.screenshotCount)"
            ]
        )
    }

    private func uniqueBundleDirectoryURL(baseDirectory: URL, suggestedName: String) -> URL {
        var candidateURL = baseDirectory.appendingPathComponent(suggestedName, isDirectory: true)
        var suffix = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = baseDirectory.appendingPathComponent("\(suggestedName)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidateURL
    }
}
