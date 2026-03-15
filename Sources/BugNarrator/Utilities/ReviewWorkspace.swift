import Foundation

enum ReviewWorkspace {
    static func availableTabs(for session: TranscriptSession) -> [ReviewWorkspaceTab] {
        var tabs: [ReviewWorkspaceTab] = [.rawTranscript, .screenshots, .extractedIssues]

        if !session.summaryText.isEmpty || session.issueExtraction != nil {
            tabs.append(.reviewSummary)
        }

        return tabs
    }

    static func clampedTab(_ selectedTab: ReviewWorkspaceTab, for session: TranscriptSession?) -> ReviewWorkspaceTab {
        guard let session else {
            return .rawTranscript
        }

        let availableTabs = availableTabs(for: session)
        return availableTabs.contains(selectedTab) ? selectedTab : .rawTranscript
    }

    static func timelineEntries(for session: TranscriptSession) -> [ReviewWorkspaceTimelineEntry] {
        var entries: [ReviewWorkspaceTimelineEntry] = []

        if session.sections.isEmpty {
            entries.append(
                ReviewWorkspaceTimelineEntry(
                    id: session.id,
                    timestamp: 0,
                    kind: .transcript,
                    title: "Full Session",
                    text: session.transcript,
                    secondaryText: nil,
                    index: nil,
                    screenshotID: nil
                )
            )
        } else {
            entries.append(contentsOf: session.sections.map { section in
                ReviewWorkspaceTimelineEntry(
                    id: section.id,
                    timestamp: section.startTime,
                    kind: .transcript,
                    title: section.title,
                    text: section.text,
                    secondaryText: nil,
                    index: nil,
                    screenshotID: nil
                )
            })
        }

        let screenshotLinkedMarkerIDs = Set(session.screenshots.compactMap(\.associatedMarkerID))

        entries.append(contentsOf: session.markers.filter { !screenshotLinkedMarkerIDs.contains($0.id) }.map { marker in
            ReviewWorkspaceTimelineEntry(
                id: marker.id,
                timestamp: marker.elapsedTime,
                kind: .marker,
                title: nil,
                text: marker.title,
                secondaryText: marker.note,
                index: marker.index,
                screenshotID: marker.screenshotID
            )
        })

        entries.append(contentsOf: session.screenshots.map { screenshot in
            let relatedMarker = screenshot.associatedMarkerID.flatMap(session.marker(with:))
            let relatedMarkerTitle = relatedMarker?.title
            let markerNote = relatedMarker?.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let secondaryText = (markerNote?.isEmpty == false) ? markerNote : nil
            return ReviewWorkspaceTimelineEntry(
                id: screenshot.id,
                timestamp: screenshot.elapsedTime,
                kind: .screenshot,
                title: nil,
                text: relatedMarkerTitle ?? "Screenshot marker",
                secondaryText: secondaryText,
                index: nil,
                screenshotID: screenshot.id
            )
        })

        return entries.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.kind.sortPriority < rhs.kind.sortPriority
            }

            return lhs.timestamp < rhs.timestamp
        }
    }

    static func selectedIssueSummary(for session: TranscriptSession) -> String {
        let selectedCount = session.issueExtraction?.issues.filter(\.isSelectedForExport).count ?? 0
        return selectedCount == 1 ? "1 issue selected" : "\(selectedCount) issues selected"
    }

    static func summaryGroups(for issues: [ExtractedIssue]) -> [ReviewSummaryIssueGroup] {
        let orderedCategories: [ExtractedIssueCategory] = [.bug, .uxIssue, .enhancement, .followUp]

        return orderedCategories.compactMap { category in
            let matchingIssues = issues.filter { $0.category == category }
            guard !matchingIssues.isEmpty else {
                return nil
            }

            return ReviewSummaryIssueGroup(category: category, issues: matchingIssues)
        }
    }
}

enum ReviewWorkspaceTab: Identifiable, CaseIterable {
    case rawTranscript
    case reviewSummary
    case screenshots
    case extractedIssues

    var id: String { title }

    var title: String {
        switch self {
        case .rawTranscript:
            return "Transcript"
        case .reviewSummary:
            return "Summary"
        case .screenshots:
            return "Screenshots"
        case .extractedIssues:
            return "Extracted Issues"
        }
    }
}

struct ReviewWorkspaceTimelineEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: TimeInterval
    let kind: ReviewWorkspaceTimelineEntryKind
    let title: String?
    let text: String
    let secondaryText: String?
    let index: Int?
    let screenshotID: UUID?

    var timeLabel: String {
        ElapsedTimeFormatter.string(from: timestamp)
    }
}

enum ReviewWorkspaceTimelineEntryKind: Equatable {
    case transcript
    case marker
    case screenshot

    var sortPriority: Int {
        switch self {
        case .transcript:
            return 2
        case .marker:
            return 0
        case .screenshot:
            return 1
        }
    }
}

struct ReviewSummaryIssueGroup: Equatable {
    let category: ExtractedIssueCategory
    let issues: [ExtractedIssue]

    var title: String {
        switch category {
        case .bug:
            return "Bugs"
        case .uxIssue:
            return "UX Issues"
        case .enhancement:
            return "Enhancements"
        case .followUp:
            return "Questions / Follow-ups"
        }
    }
}
