import Foundation

/// The bundled demo session (#374).
///
/// A brand-new user otherwise has to spend provider credit or download a
/// multi-GB local model just to find out what a BugNarrator session produces —
/// they have to wire up the workflow to learn whether the workflow is worth
/// wiring up. This is that answer, for free: a realistic transcript with
/// timeline markers, a review summary, and extracted issues across more than
/// one category.
///
/// Text only. The original ticket also wanted bundled narration audio and a
/// screenshot; both need authored binary assets, so they were dropped by
/// operator decision rather than left blocking the rest. If the audio is
/// recorded later it layers on here without rework.
///
/// Makes no network call and needs no credential — every value below is
/// literal.
enum SampleSession {
    /// Stable id so the sample can be recognised, replaced, or removed without
    /// depending on title matching.
    static let id = UUID(uuidString: "5A11E000-0000-4000-8000-000000000374") ?? UUID()

    static let title = "Sample session — Reports page review"

    /// Built at a fixed date so the fixture is deterministic in tests.
    static let createdAt = Date(timeIntervalSince1970: 1_760_000_000)

    static func make() -> TranscriptSession {
        TranscriptSession(
            id: id,
            createdAt: createdAt,
            transcript: transcript,
            duration: 96,
            model: "sample",
            languageHint: nil,
            prompt: nil,
            markers: markers,
            screenshots: [],
            issueExtraction: issueExtraction,
            isSampleSession: true
        )
    }

    // MARK: - Canned content

    private static let transcript = """
    I'm testing the Reports page on a fresh install, signed in as a regular \
    member rather than an admin.

    I'm opening Reports from the sidebar now. The table renders, and I can see \
    the date-range picker at the top.

    I'm clicking Export. I expected a CSV to download. Nothing happened — no \
    download, no error, no spinner. I clicked it twice more and still nothing.

    I'm changing the date range to last 90 days. This is slow — it took about \
    eight seconds before the table repainted, and there was no loading \
    indicator during that time, so it looked frozen.

    One more thing: the empty state. I filtered to a range with no data, and \
    the table just goes blank. There's no message explaining that the filter \
    matched nothing, so it reads like a failure rather than an empty result.

    Ending the test. The export button is the blocking issue; the other two \
    are polish.
    """

    private static let markers: [SessionMarker] = [
        SessionMarker(index: 1, elapsedTime: 12, title: "Reports page opened", screenshotID: nil),
        SessionMarker(index: 2, elapsedTime: 31, title: "Export produced no file", screenshotID: nil),
        SessionMarker(index: 3, elapsedTime: 58, title: "90-day range slow to repaint", screenshotID: nil),
        SessionMarker(index: 4, elapsedTime: 79, title: "Empty state has no message", screenshotID: nil)
    ]

    private static let issueExtraction = IssueExtractionResult(
        summary: "A member-role pass over the Reports page. Export is broken outright — the button does nothing and reports no error. Two smaller findings: a long date range takes several seconds with no loading indicator, and an empty filter result renders as a blank table with no explanation.",
        issues: [
            ExtractedIssue(
                title: "Export button does nothing on the Reports page",
                category: .bug,
                severity: .high,
                component: "Reports",
                summary: "Clicking Export produces no download, no error, and no spinner. Repeated clicks have no effect.",
                evidenceExcerpt: "I'm clicking Export. I expected a CSV to download. Nothing happened — no download, no error, no spinner.",
                timestamp: 31
            ),
            ExtractedIssue(
                title: "No loading indicator while a wide date range loads",
                category: .uxIssue,
                severity: .medium,
                component: "Reports",
                summary: "Switching to a 90-day range takes roughly eight seconds with no visible progress, so the page appears frozen.",
                evidenceExcerpt: "it took about eight seconds before the table repainted, and there was no loading indicator during that time, so it looked frozen.",
                timestamp: 58
            ),
            ExtractedIssue(
                title: "Empty filter result is indistinguishable from a failure",
                category: .uxIssue,
                severity: .low,
                component: "Reports",
                summary: "A date range matching no rows renders a blank table with no message, reading as an error rather than an empty result.",
                evidenceExcerpt: "the table just goes blank. There's no message explaining that the filter matched nothing",
                timestamp: 79
            )
        ]
    )
}
