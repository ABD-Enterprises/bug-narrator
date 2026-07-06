import Foundation

struct TrackerIssueCandidate: Equatable {
    let remoteIdentifier: String
    let title: String
    let summary: String
    let remoteURL: URL?
}

/// Helpers shared by the tracker export providers (Jira, GitHub) whose
/// implementations are byte-identical apart from the provider's display name.
enum TrackerExportSupport {
    /// Reserved words that act as operators/keywords in GitHub issue search and
    /// in Jira's JQL. The term tokenizer already strips all non-alphanumeric
    /// characters (so quotes, colons, and slashes can never reach the query),
    /// but a 3+ character keyword like `AND`/`NOT`/`ORDER` would otherwise
    /// survive as a bare token and subtly broaden or alter the duplicate search.
    /// These are common stop-words in prose, so dropping them does not weaken
    /// the keyword match for real issue text.
    private static let reservedSearchWords: Set<String> = [
        "and", "or", "not", "in", "is", "was", "null", "empty",
        "order", "by", "changed", "during", "before", "after", "on"
    ]

    /// Builds a short search phrase from an issue's most significant terms, used
    /// to look for potential duplicate issues before exporting. The phrase is a
    /// space-separated list of literal keyword terms; it must never be able to
    /// introduce a search operator/qualifier.
    static func searchTerms(for issue: ExtractedIssue) -> String {
        let source = [issue.title, issue.component, issue.summary]
            .compactMap { $0 }
            .joined(separator: " ")
        let significantTerms = source
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && !reservedSearchWords.contains($0.lowercased()) }

        return significantTerms.prefix(6).joined(separator: " ")
    }

    /// Wraps an export error with the count of issues that succeeded before the
    /// failure, so a partial export reports how much work already landed.
    static func partialExportError(
        _ error: AppError,
        providerName: String,
        successfulCount: Int
    ) -> AppError {
        guard successfulCount > 0 else {
            return error
        }

        return .exportFailure(
            "\(providerName) exported \(successfulCount) issue\(successfulCount == 1 ? "" : "s") before failing. \(error.userMessage)"
        )
    }

    /// Parses the integer (delta-seconds) form of an HTTP `Retry-After` header.
    /// The HTTP-date form is treated as absent.
    static func retryAfterSeconds(from response: HTTPURLResponse) -> Int? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces),
              let seconds = Int(raw),
              seconds >= 0 else {
            return nil
        }
        return seconds
    }

    /// A "wait and retry" suffix for a rate-limit message, using the Retry-After
    /// hint when one is available.
    static func retryAfterSuffix(_ seconds: Int?) -> String {
        if let seconds {
            return " Wait \(seconds)s and try again."
        }
        return " Wait a moment and try again."
    }

    /// Whether an HTTP status warrants a retry (secondary rate limit / server error).
    static func isTransientStatus(_ status: Int) -> Bool {
        status == 429 || (500...599).contains(status)
    }

    /// Backoff before the next retry: honor `Retry-After` if present, else
    /// exponential on the configured base (attempt is 1-based for the attempt
    /// that just failed).
    static func retryDelay(attempt: Int, retryAfterSeconds: Int?, base: Duration) -> Duration {
        if let retryAfterSeconds, retryAfterSeconds > 0 {
            return .seconds(retryAfterSeconds)
        }
        let multiplier = 1 << max(0, attempt - 1)
        return base * multiplier
    }
}
