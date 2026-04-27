import Foundation

enum TrackerExportPayloadBudget {
    static let gitHubBodyLimit = 16_000
    static let jiraTextLimit = 12_000
    static let issueSummaryLimit = 2_000
    static let evidenceLimit = 4_000
    static let noteLimit = 2_000
    static let metadataItemLimit = 12
    static let reproductionStepLimit = 10
    static let listEntryLimit = 500
    static let screenshotListLimit = 10

    static func truncated(_ value: String, maxCharacters: Int) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.count > maxCharacters else {
            return trimmedValue
        }

        let endIndex = trimmedValue.index(trimmedValue.startIndex, offsetBy: max(0, maxCharacters - 36))
        return trimmedValue[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            + " …[truncated by BugNarrator for tracker limits]"
    }

    static func limitedList(
        _ values: [String],
        maxItems: Int,
        maxCharactersPerItem: Int
    ) -> [String] {
        let trimmedValues = values.prefix(maxItems).map {
            truncated($0, maxCharacters: maxCharactersPerItem)
        }

        if values.count > maxItems {
            return trimmedValues + ["Additional items were omitted by BugNarrator to fit tracker limits."]
        }

        return trimmedValues
    }

    static func hardLimitMarkdown(_ value: String, maxCharacters: Int) -> String {
        truncated(value, maxCharacters: maxCharacters)
    }
}
