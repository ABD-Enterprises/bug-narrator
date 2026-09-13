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
    /// Jira Cloud rejects a `summary` over 255 characters or containing a
    /// newline; GitHub rejects an issue `title` over 256. Both are hard server
    /// limits, unlike the body budgets above, which are self-imposed. Jira
    /// counts UTF-16 code units while `trackerTitle` counts Characters, so a
    /// title dense in astral-plane emoji or combining sequences can sit at the
    /// Character cap and still exceed Jira's — accepted for bug titles.
    static let jiraSummaryLimit = 255
    static let gitHubTitleLimit = 256

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

    /// A title for a tracker's single-line field: whitespace runs (including
    /// newlines) collapse to one space, the result is trimmed, and anything past
    /// `maxCharacters` is cut with a single "…" — no "[truncated …]" suffix,
    /// which would consume most of a short field.
    static func trackerTitle(_ value: String, maxCharacters: Int) -> String {
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > maxCharacters else {
            return collapsed
        }

        let keep = max(0, maxCharacters - 1)
        let cut = collapsed[..<collapsed.index(collapsed.startIndex, offsetBy: keep)]
            .trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }

    static func hardLimitMarkdown(_ value: String, maxCharacters: Int) -> String {
        truncated(value, maxCharacters: maxCharacters)
    }
}
