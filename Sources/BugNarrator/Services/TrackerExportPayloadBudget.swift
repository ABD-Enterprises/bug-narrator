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
    /// limits, unlike the body budgets above, which are self-imposed. The
    /// limits are counted in UTF-16 code units, the way Jira counts them, and
    /// `trackerTitle` counts them the same way, so a title dense in
    /// astral-plane characters can never exceed what the tracker accepts.
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

    /// The live mention and cross-reference triggers in untrusted text.
    ///
    /// Every model- or transcript-derived field that reaches a tracker is run
    /// through this on the way out. GitHub autolinks **and notifies**
    /// `@mentions` in an issue title and in an issue body, and resolves
    /// `#123` cross-references there too; a tracker can render the same text
    /// again in notifications, activity feeds and search results. A third
    /// party who only controls what is on the recorded screen could
    /// otherwise put a name in the transcript and have the user's export ping
    /// arbitrary accounts in their repository, or forge a cross-reference to
    /// an unrelated issue.
    ///
    /// Only the live triggers are defanged. The fields this is used for — a
    /// tracker's single-line title and Jira's structured ADF description —
    /// are plain text, not markdown, so the block-structure, link and entity
    /// escapes the GitHub *body* needs
    /// (`GitHubExportProvider.neutralizingUntrustedMarkdown`) would only
    /// mangle them.
    static func neutralizingUntrustedMentions(_ value: String) -> String {
        value
            // A zero-width space after @/# breaks the mention and issue
            // autolinks while leaving the text visually identical.
            //
            // The regular-expression path, not the literal one: a literal
            // search matches whole grapheme clusters, so an "@" that is part
            // of a larger cluster - a combining mark, a zero-width joiner, a
            // variation selector - is never replaced and the mention
            // survives. The regex path reaches inside the cluster, and the
            // Windows port's code-unit replace does the same.
            .replacingOccurrences(of: "@", with: "@\u{200B}", options: .regularExpression)
            .replacingOccurrences(of: "#", with: "#\u{200B}", options: .regularExpression)
            // "GH-123" is an issue reference GitHub links just like "#123".
            .replacingOccurrences(of: #"(?i)(gh-)"#, with: "$1\u{200B}", options: .regularExpression)
    }

    /// A title for a tracker's single-line field: whitespace runs (including
    /// newlines) collapse to one space, the result is trimmed, and anything past
    /// `maxCharacters` is cut with a single "…" — no "[truncated …]" suffix,
    /// which would consume most of a short field.
    ///
    /// The title is untrusted text, so the mentions and cross-references in it
    /// are neutralized on the way out.
    ///
    /// The order matters. The neutralization runs **after** the whitespace
    /// collapse and **before** the length cap:
    ///
    /// - Swift's whitespace set includes the zero-width space, so a collapse
    ///   after the neutralization would turn every zero-width space back into
    ///   a plain space and the title would read "@ security-team".
    /// - The cap runs last so the field the tracker receives still fits: the
    ///   zero-width spaces count towards the limit, and cutting before the
    ///   neutralization could push a title that was already at the cap over
    ///   GitHub's 256 or Jira's 255.
    ///
    /// The cap counts UTF-16 code units, the way the tracker counts them, and
    /// the whitespace that separates words is one shared set, so the Windows
    /// port sends the same title for the same input.
    static func trackerTitle(_ value: String, maxCharacters: Int) -> String {
        let collapsed = Self.collapsingWhitespace(value)
        let neutralized = Self.neutralizingUntrustedMentions(collapsed)
        let units = Array(neutralized.utf16)
        guard units.count > maxCharacters else {
            return neutralized
        }

        // The cap counts UTF-16 code units, the way the tracker counts them:
        // Jira's 255-character limit is counted in units, so a title dense in
        // astral-plane characters is twice as long there as it is in
        // characters, and a Character-based cap would send a title the
        // tracker rejects. The Windows port counts the same units and cuts the
        // same way, so the two ports send the same title.
        var keep = max(0, maxCharacters - 1)
        if keep > 0 {
            let unitBeforeCut = units[keep - 1]
            if unitBeforeCut >= 0xD800, unitBeforeCut <= 0xDBFF {
                // The cut would land between the halves of an astral character
                // and leave a lone surrogate the JSON encoder turns into
                // U+FFFD.
                keep -= 1
            }
        }
        let cut = Self.trimmingTrailingTitleWhitespace(String(decoding: units[0..<keep], as: UTF16.self))
        return cut + "…"
    }

    /// Trims the trailing characters the Windows port's cut trims.
    ///
    /// Only the end: a leading zero-width space is part of the title, and
    /// trimming both ends would drop it here and not there.
    private static func trimmingTrailingTitleWhitespace(_ value: String) -> String {
        var scalars = value.unicodeScalars
        while let last = scalars.last, Self.trailingTitleTrimCharacters.contains(last) {
            scalars.removeLast()
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Every run of whitespace collapses to a single space.
    ///
    /// The whitespace that separates words in a tracker's single-line fields.
    /// This is exactly the set .NET's `char.IsWhiteSpace` accepts: Swift's
    /// own whitespace set also includes the zero-width space, so a title that
    /// carries one would collapse differently on the two ports, and the two
    /// ports have to send the same title.
    static func collapsingWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: Self.titleWhitespaceCharacters)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let titleWhitespaceCharacters = CharacterSet(
        charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{0085}\u{00A0}\u{1680}"
            + "\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}"
            + "\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}"
    )

    /// The characters trimmed from the end of a cut title.
    ///
    /// This is exactly the set .NET's `char.IsWhiteSpace` accepts, plus the
    /// zero-width space. Swift's whitespace set already includes U+200B, so a
    /// title cut right after a neutralized mention ("…@") is trimmed on macOS
    /// but not on Windows, and the two ports would send different titles for
    /// the same issue.
    private static let trailingTitleTrimCharacters = CharacterSet(
        charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{0085}\u{00A0}\u{1680}"
            + "\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}"
            + "\u{200B}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}"
    )

    static func hardLimitMarkdown(_ value: String, maxCharacters: Int) -> String {
        truncated(value, maxCharacters: maxCharacters)
    }
}
