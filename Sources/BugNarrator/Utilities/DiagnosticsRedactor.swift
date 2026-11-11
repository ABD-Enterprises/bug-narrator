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
        var sanitized = text
        // Remove complete known secrets before a pattern can replace only a prefix
        // and leave the remainder no longer matching the original secret.
        for exactValue in exactValues.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            sanitized = sanitized.replacingOccurrences(of: exactValue, with: "<redacted>")
        }
        for pattern in tokenPatterns {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = pattern.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: "<redacted>"
            )
        }

        // Decode Basic credentials so ordinary prose such as "Basic configuration"
        // remains useful. Work backwards because replacements change string offsets.
        if let basic = makeTokenPattern(#"\bBasic[ \t]+([A-Za-z0-9+/]+={0,2})(?![A-Za-z0-9+/=])"#, options: [.caseInsensitive]) {
            for match in basic.matches(in: sanitized, range: NSRange(sanitized.startIndex..., in: sanitized)).reversed() {
                guard let tokenRange = Range(match.range(at: 1), in: sanitized),
                      let fullRange = Range(match.range, in: sanitized) else { continue }
                var encoded = String(sanitized[tokenRange])
                encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
                guard let decoded = Data(base64Encoded: encoded),
                      decoded.contains(0x3a) else { continue }
                sanitized.replaceSubrange(fullRange, with: "<redacted>")
            }
        }

        return sanitized
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
