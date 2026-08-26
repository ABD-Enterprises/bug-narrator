import Foundation
import XCTest
@testable import BugNarrator

/// The shared macOS/Windows `transcript.md` contract (#1000).
///
/// Before this, each platform asserted parity against its own retyped literal,
/// so both suites could be green while disagreeing — the mechanism behind the
/// drift #965 catalogued. Windows' `MatchesMacTranscriptContract` pinned
/// "Mar 17, 2026 at 3:00:00 PM" for an instant macOS renders as
/// "Mar 17, 2026 at 11:00:00 AM" in America/New_York.
///
/// Both implementations now render the SAME committed input and must produce
/// the SAME committed output, under `SessionTimestampOptions.invariant`.
final class TranscriptContractFixtureTests: XCTestCase {
    private struct SharedSummaryIssue: Equatable {
        let title: String
        let category: String
        let severity: String
        let component: String
        let section: String
        let transcriptTime: String
        let confidence: String
        let requiresReview: Bool
        let summary: String
        let evidence: String
        let dedupHint: String
    }

    private enum SharedSummaryContractError: Error, CustomStringConvertible {
        case missingLine(String)
        case malformedLine(String)
        case missingField(String)

        var description: String {
            switch self {
            case .missingLine(let line):
                return "Missing line matching: \(line)"
            case .malformedLine(let line):
                return "Malformed line: \(line)"
            case .missingField(let field):
                return "Missing shared summary field: \(field)"
            }
        }
    }

    private var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // BugNarratorTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("contract-fixtures", isDirectory: true)
    }

    /// The canonical session. Kept in code AND serialized to the fixture
    /// directory so Windows can build the same input without reading Swift.
    private func canonicalSession() -> TranscriptSession {
        let created = Date(timeIntervalSince1970: 1_773_759_600) // 2026-03-17T15:00:00Z
        let marker = SessionMarker(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            index: 1,
            elapsedTime: 30,
            createdAt: created.addingTimeInterval(30),
            title: "Checkout button clipped",
            note: "Right edge is cut off at 1280 wide.",
            screenshotID: nil
        )
        return TranscriptSession(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            createdAt: created,
            transcript: "The checkout button is clipped on the right at 1280 wide.",
            duration: 120,
            model: "whisper-1",
            languageHint: "en",
            prompt: nil,
            markers: [marker]
        )
    }

    private func canonicalSummarySession() -> TranscriptSession {
        let session = canonicalSession()
        let issue = ExtractedIssue(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            title: "Checkout button clipped",
            category: .bug,
            severity: .high,
            component: "Checkout",
            summary: "The checkout button is clipped on the right at 1280 wide.",
            evidenceExcerpt: "The checkout button is clipped on the right at 1280 wide.",
            deduplicationHint: "checkout-button-clipped",
            timestamp: 30,
            relatedScreenshotIDs: [],
            confidence: 0.72,
            requiresReview: true,
            isSelectedForExport: false,
            sectionTitle: "Opening Notes",
            reproductionSteps: [
                IssueReproductionStep(
                    id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
                    instruction: "Open the checkout page at 1280px width.",
                    expectedResult: "The primary action remains fully visible.",
                    actualResult: "The right edge of the checkout button is clipped.",
                    timestamp: 30,
                    screenshotID: nil
                )
            ],
            screenshotAnnotations: [],
            note: "Investigate responsive width handling."
        )

        var reviewSession = session
        reviewSession.issueExtraction = IssueExtractionResult(
            generatedAt: session.createdAt.addingTimeInterval(300),
            summary: "The checkout button is clipped on the right at 1280 wide.",
            guidanceNote: "Review before export.",
            issues: [issue]
        )
        return reviewSession
    }

    /// Regenerates the golden from the real renderer and diffs it. A change to
    /// `markdownContent` that the fixture does not expect fails here, which is
    /// the whole point — the fixture is a contract, not a snapshot to rubber-stamp.
    func testTranscriptMarkdownMatchesTheCommittedGolden() throws {
        let produced = canonicalSession().markdownContent(timestampOptions: .invariant)
        let goldenURL = fixturesDirectory.appendingPathComponent("transcript.golden.md")

        if ProcessInfo.processInfo.environment["BUGNARRATOR_UPDATE_CONTRACT_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(
                at: fixturesDirectory,
                withIntermediateDirectories: true
            )
            try produced.write(to: goldenURL, atomically: true, encoding: .utf8)
            return
        }

        // xcodebuild does not forward arbitrary shell env vars into the XCTest
        // runner process, so the remediation text must name the TEST_RUNNER_
        // form that the harness translates into the bare env this test reads.
        guard let golden = try? String(contentsOf: goldenURL, encoding: .utf8) else {
            return XCTFail(
                "Missing \(goldenURL.path). Regenerate with TEST_RUNNER_BUGNARRATOR_UPDATE_CONTRACT_FIXTURES=1."
            )
        }

        XCTAssertEqual(
            produced,
            golden,
            "transcript.md drifted from the committed contract. If the change is intended, "
                + "regenerate with TEST_RUNNER_BUGNARRATOR_UPDATE_CONTRACT_FIXTURES=1 and expect the Windows suite to fail until it is updated too."
        )
    }

    /// The pinned rendering is the point of the whole exercise: without it the
    /// golden would differ per machine and could never bind two platforms.
    func testInvariantTimestampIsMachineIndependentAndASCII() {
        let rendered = canonicalSession().markdownContent(timestampOptions: .invariant)

        XCTAssertTrue(
            rendered.contains("- Recorded: Mar 17, 2026 at 3:00:00 PM"),
            "Invariant rendering must be UTC and ASCII — the exact line Windows pins."
        )
        XCTAssertFalse(
            rendered.unicodeScalars.contains { $0.value == 0x202F || $0.value == 0x00A0 },
            "No U+202F/U+00A0 may survive into the contract. Apple's formatter emits U+202F "
                + "before AM/PM and .NET emits ASCII, so an unnormalized fixture would be "
                + "byte-unmatchable while looking identical."
        )
    }

    /// Shipped behavior must not move. The default stays locale/timezone-local,
    /// which is what a user reading their own export expects.
    func testDefaultRenderingIsUnchangedAndLocal() {
        let session = canonicalSession()

        XCTAssertEqual(
            session.markdownContent,
            session.markdownContent(timestampOptions: .current),
            "The bare property must remain exactly today's behavior."
        )

        if TimeZone.current.secondsFromGMT(for: session.createdAt) != 0 {
            XCTAssertNotEqual(
                session.markdownContent,
                session.markdownContent(timestampOptions: .invariant),
                "Outside UTC the local rendering must differ — that difference is the bug Windows could not see."
            )
        }
    }

    func testSummaryMarkdownSharedSubsetMatchesTheCommittedGolden() throws {
        let produced = try sharedSummaryFixture(from: canonicalSummarySession().summaryMarkdownContent)
        let goldenURL = fixturesDirectory.appendingPathComponent("summary.golden.md")

        if ProcessInfo.processInfo.environment["BUGNARRATOR_UPDATE_CONTRACT_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(
                at: fixturesDirectory,
                withIntermediateDirectories: true
            )
            try produced.write(to: goldenURL, atomically: true, encoding: .utf8)
            return
        }

        let goldenData = try XCTUnwrap(
            try? Data(contentsOf: goldenURL),
            "Missing \(goldenURL.path). Regenerate with TEST_RUNNER_BUGNARRATOR_UPDATE_CONTRACT_FIXTURES=1."
        )

        XCTAssertFalse(
            goldenData.starts(with: [0xEF, 0xBB, 0xBF]),
            "summary.golden.md must not carry a UTF-8 BOM."
        )
        XCTAssertFalse(
            goldenData.contains(0x0D),
            "summary.golden.md must be LF-only. contract-fixtures/** is pinned to eol=lf."
        )

        XCTAssertEqual(
            goldenData,
            Data(produced.utf8),
            "summary.md shared-subset drifted from the committed contract. If the change is intended, "
                + "regenerate with TEST_RUNNER_BUGNARRATOR_UPDATE_CONTRACT_FIXTURES=1 and expect the Windows suite to fail until it is updated too."
        )
    }

    private func sharedSummaryFixture(from markdown: String) throws -> String {
        let lines = markdown.components(separatedBy: "\n")

        guard lines.first == "# BugNarrator Review Output" else {
            throw SharedSummaryContractError.malformedLine(lines.first ?? "<missing title>")
        }
        guard lines.contains(where: { $0.hasPrefix("- Recorded: ") }) else {
            throw SharedSummaryContractError.missingLine("- Recorded: ...")
        }

        let duration = try value(in: lines, prefixedBy: "- Duration: ")
        let model = try value(in: lines, prefixedBy: "- Transcript Model: ")
        let summary = try summaryBody(in: lines)
        let guidance = try guidanceNote(in: lines)
        let issues = try sharedIssues(in: lines)

        var fixtureLines = [
            "# BugNarrator Review Output",
            "",
            "- Duration: \(duration)",
            "- Transcript Model: \(model)",
            "",
            "## Summary",
            "",
            summary,
            "",
            "> \(guidance)",
            "",
            "## Shared Extracted Issue Fields",
            ""
        ]

        for issue in issues {
            fixtureLines.append("### \(issue.title)")
            fixtureLines.append("")
            fixtureLines.append("- Category: \(issue.category)")
            fixtureLines.append("- Severity: \(issue.severity)")
            fixtureLines.append("- Component: \(issue.component)")
            fixtureLines.append("- Section: \(issue.section)")
            fixtureLines.append("- Transcript Time: \(issue.transcriptTime)")
            fixtureLines.append("- Confidence: \(issue.confidence)")
            fixtureLines.append("- Requires Review: \(issue.requiresReview ? "Yes" : "No")")
            fixtureLines.append("- Summary: \(issue.summary)")
            fixtureLines.append("- Evidence: \(issue.evidence)")
            fixtureLines.append("- Dedup Hint: \(issue.dedupHint)")
            fixtureLines.append("")
        }

        fixtureLines.removeLast()
        return fixtureLines.joined(separator: "\n")
    }

    private func summaryBody(in lines: [String]) throws -> String {
        guard let summaryIndex = lines.firstIndex(of: "## Summary") else {
            throw SharedSummaryContractError.missingLine("## Summary")
        }
        let bodyIndex = summaryIndex + 2
        guard bodyIndex < lines.count, !lines[bodyIndex].isEmpty else {
            throw SharedSummaryContractError.missingField("summary body")
        }

        return lines[bodyIndex]
    }

    private func guidanceNote(in lines: [String]) throws -> String {
        guard let guidanceLine = lines.first(where: { $0.hasPrefix("> ") }) else {
            throw SharedSummaryContractError.missingLine("> guidance note")
        }

        return String(guidanceLine.dropFirst(2))
    }

    private func sharedIssues(in lines: [String]) throws -> [SharedSummaryIssue] {
        var issues: [SharedSummaryIssue] = []
        var currentCategory: String?
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("## "), line != "## Summary" {
                currentCategory = String(line.dropFirst(3))
                index += 1
                continue
            }

            guard line.hasPrefix("- **") else {
                index += 1
                continue
            }

            guard let category = currentCategory else {
                throw SharedSummaryContractError.missingField("issue category")
            }

            let bullet = String(line.dropFirst(4))
            guard let titleEnd = bullet.range(of: "**: ") else {
                throw SharedSummaryContractError.malformedLine(line)
            }

            let title = String(bullet[..<titleEnd.lowerBound])
            let summary = String(bullet[titleEnd.upperBound...])
            var severity: String?
            var component: String?
            var section: String?
            var transcriptTime: String?
            var confidence: String?
            var requiresReview = false
            var evidence: String?
            var dedupHint: String?

            index += 1
            while index < lines.count {
                let detailLine = lines[index]
                if detailLine.hasPrefix("- **") || detailLine.hasPrefix("## ") {
                    break
                }

                if detailLine.hasPrefix("  Context: ") {
                    let context = String(detailLine.dropFirst("  Context: ".count))
                    for part in context.components(separatedBy: "  •  ") {
                        if let value = part.stripPrefix("severity ") {
                            severity = value.capitalized
                        } else if let value = part.stripPrefix("confidence ") {
                            confidence = value
                        } else if part == "review needed" {
                            requiresReview = true
                        } else if part.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil {
                            transcriptTime = part
                        } else if component == nil {
                            component = part
                        } else {
                            section = part
                        }
                    }
                } else if detailLine.hasPrefix("  Evidence: ") {
                    evidence = String(detailLine.dropFirst("  Evidence: ".count))
                } else if detailLine.hasPrefix("  Dedup hint: ") {
                    dedupHint = String(detailLine.dropFirst("  Dedup hint: ".count))
                }

                index += 1
            }

            guard let severity,
                  let component,
                  let section,
                  let transcriptTime,
                  let confidence,
                  let evidence,
                  let dedupHint else {
                throw SharedSummaryContractError.missingField("macOS issue details for \(title)")
            }

            issues.append(
                SharedSummaryIssue(
                    title: title,
                    category: category,
                    severity: severity,
                    component: component,
                    section: section,
                    transcriptTime: transcriptTime,
                    confidence: confidence,
                    requiresReview: requiresReview,
                    summary: summary,
                    evidence: evidence,
                    dedupHint: dedupHint
                )
            )
        }

        guard !issues.isEmpty else {
            throw SharedSummaryContractError.missingField("shared extracted issues")
        }

        return issues
    }

    private func value(in lines: [String], prefixedBy prefix: String) throws -> String {
        guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else {
            throw SharedSummaryContractError.missingLine(prefix)
        }

        return String(line.dropFirst(prefix.count))
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }

        return String(dropFirst(prefix.count))
    }
}
