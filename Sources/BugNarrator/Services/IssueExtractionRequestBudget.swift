import Foundation

enum IssueExtractionRequestBudget {
    static let maximumTranscriptCharacters = 24_000
    static let maximumScreenshotCount = 4
    static let maximumSingleScreenshotBytes = 2 * 1_024 * 1_024
    static let maximumTotalScreenshotBytes = 6 * 1_024 * 1_024

    static func transcriptLines(for session: TranscriptSession) -> [String] {
        var remainingCharacters = maximumTranscriptCharacters
        var lines: [String] = []
        var omittedCharacterCount = 0

        func appendBudgetedText(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }

            if trimmed.count <= remainingCharacters {
                lines.append(trimmed)
                remainingCharacters -= trimmed.count
                return
            }

            if remainingCharacters > 0 {
                let endIndex = trimmed.index(trimmed.startIndex, offsetBy: remainingCharacters)
                lines.append(String(trimmed[..<endIndex]))
            }
            omittedCharacterCount += trimmed.count - max(remainingCharacters, 0)
            remainingCharacters = 0
        }

        if session.sections.isEmpty {
            appendBudgetedText(session.transcript)
        } else {
            for section in session.sections {
                guard remainingCharacters > 0 else {
                    omittedCharacterCount += section.text.count
                    continue
                }

                lines.append("## \(section.title) [\(section.timeRangeLabel)]")
                if !section.screenshotIDs.isEmpty {
                    let fileNames = section.screenshotIDs.compactMap { session.screenshot(with: $0)?.fileName }
                    if !fileNames.isEmpty {
                        lines.append("Screenshots: \(fileNames.joined(separator: ", "))")
                    }
                }
                appendBudgetedText(section.text)
                lines.append("")
            }
        }

        if omittedCharacterCount > 0 {
            lines.append("[Budget note: omitted \(omittedCharacterCount) transcript character(s) from the extraction request. Export or inspect the full transcript locally if needed.]")
        }

        return lines
    }

    static func fileSize(for url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }

        return (attributes[.size] as? NSNumber)?.intValue
    }
}
