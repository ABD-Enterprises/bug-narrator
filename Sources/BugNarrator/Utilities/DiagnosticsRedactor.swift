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

    private static let tokenPatterns: [NSRegularExpression] = [
        makeTokenPattern(#"sk-[A-Za-z0-9_-]+"#),
        makeTokenPattern(#"github_pat_[A-Za-z0-9_]+"#),
        makeTokenPattern(#"gh[pousr]_[A-Za-z0-9]+"#, options: [.caseInsensitive]),
        makeTokenPattern(#"ATATT3xFfGF0[A-Za-z0-9_\-=]+"#),
        makeTokenPattern(#"Bearer\s+[A-Za-z0-9._~+/\-]+=*"#, options: [.caseInsensitive])
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
        let source = text as NSString
        let entireRange = NSRange(location: 0, length: source.length)
        var ranges = tokenPatterns.flatMap { pattern in
            pattern.matches(in: text, range: entireRange).map(\.range)
        }

        // Find every sensitive range before replacing anything. Replacing one
        // prefix first can split another token and prevent its complete match.
        for exactValue in exactValues where !exactValue.isEmpty {
            var searchRange = entireRange
            while searchRange.length > 0 {
                let match = source.range(of: exactValue, range: searchRange)
                guard match.location != NSNotFound else { break }
                ranges.append(match)
                let next = NSMaxRange(match)
                searchRange = NSRange(location: next, length: source.length - next)
            }
        }

        // Decode Basic credentials so ordinary "Basic configuration" prose stays.
        if let basic = makeTokenPattern(#"\bBasic[ \t]+([A-Za-z0-9+/]+={0,2})(?![A-Za-z0-9+/=])"#, options: [.caseInsensitive]) {
            for match in basic.matches(in: text, range: entireRange) {
                var encoded = source.substring(with: match.range(at: 1))
                encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
                if let decoded = Data(base64Encoded: encoded), decoded.contains(0x3a) {
                    ranges.append(match.range)
                }
            }
        }

        var merged: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            if let last = merged.last, range.location <= NSMaxRange(last) {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else {
                merged.append(range)
            }
        }
        let sanitized = NSMutableString(string: text)
        for range in merged.reversed() {
            sanitized.replaceCharacters(in: range, with: "<redacted>")
        }
        return sanitized as String
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

    private static func makeTokenPattern(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }
}
