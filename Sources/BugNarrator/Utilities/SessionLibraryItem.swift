import Foundation

protocol SessionLibraryItem: Identifiable {
    var id: UUID { get }
    var createdAt: Date { get }
    var searchIndexText: String { get }
    var isPendingTranscription: Bool { get }
}

struct SessionLibraryEntry: SessionLibraryItem, Equatable, Codable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let title: String
    let preview: String
    let summaryText: String
    let duration: TimeInterval
    let markerCount: Int
    let screenshotCount: Int
    let issueCount: Int
    let isPendingTranscription: Bool
    let recoveredSourceFileName: String?
    let searchIndexText: String

    init(session: TranscriptSession) {
        id = session.id
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        title = session.title
        preview = session.preview
        summaryText = session.summaryText
        duration = session.duration
        markerCount = session.markerCount
        screenshotCount = session.screenshotCount
        issueCount = session.issueCount
        isPendingTranscription = session.requiresTranscriptionRetry
        recoveredSourceFileName = session.recoveredSourceFileName ?? session.pendingTranscription?.recoveredSourceFileName
        searchIndexText = Self.makeMetadataSearchIndexText(
            title: title,
            preview: preview,
            summaryText: summaryText,
            markers: session.markers,
            issues: session.issueExtraction?.issues ?? [],
            pendingTranscription: session.pendingTranscription
        )
    }

    private static func makeMetadataSearchIndexText(
        title: String,
        preview: String,
        summaryText: String,
        markers: [SessionMarker],
        issues: [ExtractedIssue],
        pendingTranscription: PendingTranscription?
    ) -> String {
        let markerTerms = markers.flatMap { marker in
            [
                marker.title,
                marker.note
            ].compactMap {
                $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
        }
        let issueTerms = issues.flatMap { issue in
            [
                issue.title,
                issue.summary,
                issue.component,
                issue.deduplicationHint
            ].compactMap { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
        }
        let pendingTerms = pendingTranscription.map { pending in
            [
                pending.failureReason.recoveryMessage,
                pending.recoveredSourceFileName
            ].compactMap {
                $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
        } ?? []

        return ([title, preview, summaryText] + markerTerms + issueTerms + pendingTerms)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct SessionLibrarySnapshot<Item: SessionLibraryItem> {
    let filteredItems: [Item]
    let counts: [SessionLibraryDateFilter: Int]
    let emptyState: SessionLibraryEmptyState?
}
