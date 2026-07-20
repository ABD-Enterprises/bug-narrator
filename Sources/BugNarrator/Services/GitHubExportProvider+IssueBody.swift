import Foundation

extension GitHubExportProvider {
    static func neutralizingUntrustedMarkdown(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            var escaped = line
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                // A zero-width space after @/# breaks GitHub's mention and issue
                // autolinks (and defeats `# heading` injection) while leaving the
                // text visually identical.
                .replacingOccurrences(of: "@", with: "@\u{200B}")
                .replacingOccurrences(of: "#", with: "#\u{200B}")
            if let first = escaped.first, "-*+|=`~".contains(first) {
                escaped = "\\" + escaped
            }
            return escaped
        }
        return lines.joined(separator: "\n")
    }

    func makeIssueBody(
        issue: ExtractedIssue,
        session: TranscriptSession,
        exportFingerprint: String?
    ) throws -> String {
        var lines: [String] = [
            "## Summary",
            Self.neutralizingUntrustedMarkdown(
                TrackerExportPayloadBudget.truncated(
                    issue.summary,
                    maxCharacters: TrackerExportPayloadBudget.issueSummaryLimit
                )
            ),
            "",
            "## Evidence",
            Self.neutralizingUntrustedMarkdown(
                TrackerExportPayloadBudget.truncated(
                    issue.evidenceExcerpt,
                    maxCharacters: TrackerExportPayloadBudget.evidenceLimit
                )
            ),
            ""
        ]

        if let timestampLabel = issue.timestampLabel {
            lines.append("- Transcript time: `\(timestampLabel)`")
        }

        lines.append("- Severity: \(issue.severity.rawValue)")

        if let component = issue.component?.trimmingCharacters(in: .whitespacesAndNewlines),
           !component.isEmpty {
            lines.append("- Component: \(Self.neutralizingUntrustedMarkdown(component))")
        }

        lines.append("- Deduplication hint: `\(issue.deduplicationHint)`")

        if let sectionTitle = issue.sectionTitle, !sectionTitle.isEmpty {
            lines.append("- Transcript section: \(Self.neutralizingUntrustedMarkdown(sectionTitle))")
        }

        if let confidenceLabel = issue.confidenceLabel {
            lines.append("- Confidence: \(confidenceLabel)")
        }

        if issue.requiresReview {
            lines.append("- Review needed: Yes")
        }

        if let note = issue.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            lines.append("")
            // `note` is set by our own dedup policy (trackerContextNote) and may
            // deliberately contain a "Related to #123" cross-link, so it is not
            // neutralized here.
            lines.append("## Tracker Context")
            lines.append(
                TrackerExportPayloadBudget.truncated(
                    note,
                    maxCharacters: TrackerExportPayloadBudget.noteLimit
                )
            )
        }

        if !issue.reproductionSteps.isEmpty {
            lines.append("")
            lines.append("## Reproduction Steps")

            for (index, step) in issue.reproductionSteps.prefix(TrackerExportPayloadBudget.reproductionStepLimit).enumerated() {
                lines.append(
                    "\(index + 1). \(Self.neutralizingUntrustedMarkdown(TrackerExportPayloadBudget.truncated(step.instruction, maxCharacters: TrackerExportPayloadBudget.listEntryLimit)))"
                )

                if let expectedResult = step.expectedResult?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !expectedResult.isEmpty {
                    lines.append("   - Expected: \(Self.neutralizingUntrustedMarkdown(TrackerExportPayloadBudget.truncated(expectedResult, maxCharacters: TrackerExportPayloadBudget.listEntryLimit)))")
                }

                if let actualResult = step.actualResult?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !actualResult.isEmpty {
                    lines.append("   - Actual: \(Self.neutralizingUntrustedMarkdown(TrackerExportPayloadBudget.truncated(actualResult, maxCharacters: TrackerExportPayloadBudget.listEntryLimit)))")
                }

                if let reference = reproductionStepReference(step, session: session) {
                    lines.append("   - Reference: \(reference)")
                }
            }
        }

        let annotationLines = try annotatedScreenshotLines(issue: issue, session: session)
        if !annotationLines.isEmpty {
            lines.append("")
            lines.append("## Annotated Screenshots")
            lines.append(
                contentsOf: TrackerExportPayloadBudget.limitedList(
                    annotationLines,
                    maxItems: TrackerExportPayloadBudget.screenshotListLimit,
                    maxCharactersPerItem: TrackerExportPayloadBudget.listEntryLimit
                )
            )
        }

        let screenshots = session.screenshots(for: issue)
        if !screenshots.isEmpty {
            lines.append("")
            lines.append("## Related Screenshots")
            for screenshot in screenshots.prefix(TrackerExportPayloadBudget.screenshotListLimit) {
                lines.append("- \(screenshot.fileName) (`\(screenshot.timeLabel)`) - attach manually from the exported session bundle if needed.")
            }
        }

        lines.append("")
        lines.append("## Source")
        lines.append("Exported from BugNarrator. Review against the raw transcript before triage.")

        let footer = exportFingerprint.map { "\n\n\(TrackerExportFingerprint.marker(for: $0))" } ?? ""
        return TrackerExportPayloadBudget.hardLimitMarkdown(
            lines.joined(separator: "\n"),
            maxCharacters: TrackerExportPayloadBudget.gitHubBodyLimit - footer.count
        ) + footer
    }

    private func reproductionStepReference(_ step: IssueReproductionStep, session: TranscriptSession) -> String? {
        var parts: [String] = []

        if let timestampLabel = step.timestampLabel {
            parts.append("Transcript `\(timestampLabel)`")
        }

        if let screenshotID = step.screenshotID,
           let screenshot = session.screenshot(with: screenshotID) {
            parts.append("Screenshot `\(screenshot.fileName)` (`\(screenshot.timeLabel)`)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "  •  ")
    }

    private func annotatedScreenshotLines(issue: ExtractedIssue, session: TranscriptSession) throws -> [String] {
        try annotationRenderer.annotatedScreenshotExports(for: issue, session: session).map { export in
            if let renderedFileName = export.renderedFileName {
                return "- \(renderedFileName) from `\(export.screenshotFileName)` (`\(export.timeLabel)`) — \(export.summaries)"
            }

            return "- \(export.screenshotFileName) (`\(export.timeLabel)`) — \(export.summaries)"
        }
    }
}
