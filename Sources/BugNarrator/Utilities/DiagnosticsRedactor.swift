import Foundation

enum DiagnosticsRedactor {
    private static let explicitSensitiveKeys: Set<String> = [
        "apiKey",
        "api_key",
        "authorization",
        "token",
        "githubToken",
        "jiraToken",
        "password",
        "secret",
        "transcript",
        "rawTranscript",
        "transcriptText",
        "evidence",
        "evidenceExcerpt",
        "requestBody",
        "responseBody"
    ]

    /// A pattern that finds credentials, and the check that says whether what
    /// it found is one.
    ///
    /// A pattern can match a word that only looks like a credential, so the
    /// matched text is checked before it is replaced.
    private struct TokenRule: Sendable {
        let regex: NSRegularExpression
        let isCredential: @Sendable (String) -> Bool
    }

    private static let tokenRules: [TokenRule] = [
        makeRule(#"sk-[A-Za-z0-9_-]+"#),
        makeRule(#"github_pat_[A-Za-z0-9_]+"#),
        makeRule(#"gh[pousr]_[A-Za-z0-9]+"#, options: [.caseInsensitive]),
        makeRule(#"Bearer\s+[A-Za-z0-9._\-]+"#, options: [.caseInsensitive]),
        // Jira and other Basic-authenticated services travel as
        // "Basic <base64>", the way the Windows port already redacts them.
        //
        // The word "Basic" also starts ordinary prose — "Basic
        // authentication failed" — and redacting that hides the very error
        // the user opened the bundle to read. A Basic credential is the
        // base64 of "user:secret", so the match is decoded and checked for
        // the colon before it is replaced.
        makeRule(
            #"Basic\s+[A-Za-z0-9+/=]{8,}"#,
            options: [.caseInsensitive],
            isCredential: isBase64EncodedCredential
        ),
        // An Atlassian API token carries a fixed ATATT3xFfGF0 prefix. It
        // normally travels inside a Basic header, but a token pasted bare into
        // a log line — a settings dump, a copied error — must not survive
        // into a debug bundle either.
        makeRule(#"ATATT3xFfGF0[A-Za-z0-9_\-=]{20,}"#)
    ].compactMap { $0 }

    static func sensitiveValues(in metadata: [String: String]) -> [String] {
        var values = Set<String>()

        for (key, value) in metadata {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }

            if shouldRedactMetadataValue(for: normalizedKey, value: trimmedValue) {
                values.insert(trimmedValue)
            }
        }

        return values.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs < rhs
            }

            return lhs.count > rhs.count
        }
    }

    static func sanitizeMetadata(_ metadata: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: metadata.map { key, value in
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if shouldRedactMetadataValue(for: normalizedKey, value: value) {
                return (normalizedKey, "<redacted>")
            }

            let sanitizedValue = sanitizeFreeformText(value)
            if sanitizedValue != value {
                return (normalizedKey, "<redacted>")
            }

            return (normalizedKey, sanitizedValue)
        })
    }

    static func sanitizeFreeformText(_ text: String, redactingExactValues exactValues: [String] = []) -> String {
        var sanitized = text
        for rule in tokenRules {
            sanitized = redact(rule: rule, in: sanitized)
        }

        for exactValue in exactValues where !exactValue.isEmpty {
            sanitized = sanitized.replacingOccurrences(of: exactValue, with: "<redacted>")
        }

        return sanitized
    }

    /// Replaces the matches of `rule` that are credentials.
    ///
    /// A rule can match a word that only looks like a credential, so the
    /// matched text is checked before it is replaced. A match that is not a
    /// credential is left exactly as it was.
    private static func redact(rule: TokenRule, in text: String) -> String {
        let matches = rule.regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            guard rule.isCredential(String(text[range])) else { continue }
            result += String(text[cursor..<range.lowerBound])
            result += "<redacted>"
            cursor = range.upperBound
        }
        result += String(text[cursor...])
        return result
    }

    private static func shouldRedactMetadataValue(for key: String, value: String) -> Bool {
        let lowercasedKey = key.lowercased()
        if explicitSensitiveKeys.contains(key) ||
            explicitSensitiveKeys.contains(lowercasedKey) ||
            lowercasedKey.contains("token") ||
            lowercasedKey.contains("apikey") ||
            lowercasedKey.contains("api-key") ||
            lowercasedKey.contains("authorization") ||
            lowercasedKey.contains("password") ||
            lowercasedKey.contains("secret") ||
            lowercasedKey.contains("transcript") {
            return true
        }

        return sanitizeFreeformText(value) != value
    }

    private static func makeRule(
        _ pattern: String,
        options: NSRegularExpression.Options = [],
        isCredential: @escaping @Sendable (String) -> Bool = { _ in true }
    ) -> TokenRule? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        return TokenRule(regex: regex, isCredential: isCredential)
    }

    /// Whether `text` is a Basic credential: the word followed by something
    /// that decodes to `user:secret`.
    ///
    /// The base64 of a credential always carries the colon that separates the
    /// two halves, so decoding is what tells a credential from an ordinary
    /// word that happens to follow the word "Basic".
    private static func isBase64EncodedCredential(_ text: String) -> Bool {
        let parts = text.split(whereSeparator: { $0.isWhitespace })
        guard parts.count == 2 else { return false }
        guard let data = Data(base64Encoded: String(parts[1])), !data.isEmpty else { return false }
        guard let decoded = String(data: data, encoding: .utf8) else { return false }
        return decoded.contains(":")
    }
}
