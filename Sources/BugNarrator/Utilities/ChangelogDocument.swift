import Foundation

struct ChangelogDocument: Equatable {
    let title: String
    let markdown: String
    let latestHighlights: [String]
    let releases: [ChangelogRelease]

    init(title: String = "What’s New", markdown: String) {
        self.title = title
        self.markdown = markdown
        self.releases = Self.extractReleases(from: markdown)
        self.latestHighlights = Array(releases.first?.notes.map(\.text).prefix(3) ?? [])
    }

    init(bundle: Bundle = .main) {
        if let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
           let data = try? Data(contentsOf: url),
           let markdown = String(data: data, encoding: .utf8),
           !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.init(markdown: markdown)
            return
        }

        self.init(markdown: """
        # Changelog

        ## 1.0.0

        - Initial BugNarrator product release.
        """)
    }

    init() {
        self.init(bundle: .main)
    }

    var attributedMarkdown: AttributedString {
        if let parsed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return parsed
        }

        return AttributedString(markdown)
    }

    private static func extractReleases(from markdown: String) -> [ChangelogRelease] {
        var releases: [ChangelogRelease] = []
        var currentTitle: String?
        var currentNotes: [ChangelogReleaseNote] = []

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("## ") {
                if let currentTitle, !currentNotes.isEmpty {
                    releases.append(ChangelogRelease(title: currentTitle, notes: currentNotes))
                }

                currentTitle = String(line.dropFirst(3))
                currentNotes = []
                continue
            }

            guard currentTitle != nil, line.hasPrefix("- ") else {
                continue
            }

            currentNotes.append(ChangelogReleaseNote(rawText: String(line.dropFirst(2))))
        }

        if let currentTitle, !currentNotes.isEmpty {
            releases.append(ChangelogRelease(title: currentTitle, notes: currentNotes))
        }

        return releases
    }
}

struct ChangelogRelease: Equatable, Identifiable {
    let title: String
    let notes: [ChangelogReleaseNote]

    var id: String { title }

    var version: String {
        title.components(separatedBy: " - ").first ?? title
    }

    var date: String? {
        let parts = title.components(separatedBy: " - ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : nil
    }
}

struct ChangelogReleaseNote: Equatable {
    let category: String?
    let text: String

    init(rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let endIndex = trimmed.firstIndex(of: "]") else {
            category = nil
            text = trimmed
            return
        }

        category = String(trimmed[trimmed.index(after: trimmed.startIndex)..<endIndex])
        text = String(trimmed[trimmed.index(after: endIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
