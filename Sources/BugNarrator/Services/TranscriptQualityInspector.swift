import Foundation

struct TranscriptQualityInspector {
    private enum Defaults {
        static let minimumUsefulCharacterCount = 12
        static let repeatedPhraseMinimumWords = 4
        static let repeatedPhraseMinimumCount = 6
        static let abruptEndingMinimumWords = 25
    }

    func findings(for transcript: String) -> [TranscriptQualityFinding] {
        let normalized = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        guard !normalized.isEmpty else {
            return [
                TranscriptQualityFinding(
                    kind: .shortTranscript,
                    severity: .error,
                    message: "The transcript is empty."
                )
            ]
        }

        var findings: [TranscriptQualityFinding] = []
        if normalized.count < Defaults.minimumUsefulCharacterCount {
            findings.append(
                TranscriptQualityFinding(
                    kind: .shortTranscript,
                    severity: .warning,
                    message: "The transcript is unusually short. Confirm the recording captured the expected audio."
                )
            )
        }

        if let repeatedPhrase = repeatedPhrase(in: normalized) {
            findings.append(
                TranscriptQualityFinding(
                    kind: .repeatedText,
                    severity: .warning,
                    message: "The transcript contains repeated text near \"\(repeatedPhrase)\". Review before relying on it."
                )
            )
        }

        if appearsAbruptlyCutOff(normalized) {
            findings.append(
                TranscriptQualityFinding(
                    kind: .abruptEnding,
                    severity: .warning,
                    message: "The transcript appears to end mid-thought. Check whether the recording or transcription was cut off."
                )
            )
        }

        return findings
    }

    private func repeatedPhrase(in transcript: String) -> String? {
        let words = transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard words.count >= Defaults.repeatedPhraseMinimumWords * Defaults.repeatedPhraseMinimumCount else {
            return nil
        }

        var counts: [String: Int] = [:]
        let windowSize = Defaults.repeatedPhraseMinimumWords
        for index in 0...(words.count - windowSize) {
            let phrase = words[index..<(index + windowSize)].joined(separator: " ")
            counts[phrase, default: 0] += 1
            if counts[phrase, default: 0] >= Defaults.repeatedPhraseMinimumCount {
                return phrase
            }
        }

        return nil
    }

    private func appearsAbruptlyCutOff(_ transcript: String) -> Bool {
        let words = transcript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count >= Defaults.abruptEndingMinimumWords else {
            return false
        }

        guard let lastCharacter = transcript.last else {
            return false
        }

        if ".!?)]}\"'".contains(lastCharacter) {
            return false
        }

        let trailingWords = words.suffix(3).map { $0.lowercased() }
        let weakEndings: Set<String> = [
            "and",
            "but",
            "or",
            "so",
            "because",
            "that",
            "to",
            "the",
            "a",
            "an",
            "of",
            "for",
            "with"
        ]

        return trailingWords.contains { weakEndings.contains($0.trimmingCharacters(in: .punctuationCharacters)) }
    }
}
