import Foundation

struct TranscriptQualityInspector {
    private enum Defaults {
        static let minimumUsefulCharacterCount = 12
        static let repeatedPhraseMinimumWords = 4
        static let repeatedPhraseMinimumCount = 4
        static let repeatedSingleWordMinimumCount = 6
        static let consecutiveRepeatedPhraseMinimumWords = 2
        static let consecutiveRepeatedPhraseMinimumCount = 4
        static let consecutiveRepeatedPhraseMaximumWords = 8
        static let unexpectedScriptMinimumScalars = 4
        static let unexpectedScriptMinimumScalarsInLikelyEnglish = 2
        static let likelyEnglishMinimumLatinScalars = 20
        static let unexpectedScriptMinimumRatio = 0.04
        static let abruptEndingMinimumWords = 25
        static let boilerplateMinimumLatinScalars = 8
        static let boilerplateMaximumUsefulWords = 18
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

        if let boilerplatePhrase = boilerplateHallucination(in: normalized) {
            findings.append(
                TranscriptQualityFinding(
                    kind: .boilerplateText,
                    severity: .warning,
                    message: "The transcript contains likely transcription boilerplate near \"\(boilerplatePhrase)\". Confirm the recording captured tester narration before relying on it."
                )
            )
        }

        if containsUnexpectedCJKScript(normalized) {
            findings.append(
                TranscriptQualityFinding(
                    kind: .unexpectedLanguageScript,
                    severity: .warning,
                    message: "The transcript contains CJK characters. If this was English narration, keep the language hint set to en and retry transcription before relying on it."
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

        if let repeatedWord = repeatedSingleWord(in: words) {
            return repeatedWord
        }

        if let consecutivePhrase = consecutiveRepeatedPhrase(in: words) {
            return consecutivePhrase
        }

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

    private func repeatedSingleWord(in words: [String]) -> String? {
        guard words.count >= Defaults.repeatedSingleWordMinimumCount else {
            return nil
        }

        var currentWord: String?
        var currentCount = 0
        for word in words {
            if word == currentWord {
                currentCount += 1
            } else {
                currentWord = word
                currentCount = 1
            }

            if currentCount >= Defaults.repeatedSingleWordMinimumCount {
                return word
            }
        }

        return nil
    }

    private func consecutiveRepeatedPhrase(in words: [String]) -> String? {
        guard words.count >= Defaults.consecutiveRepeatedPhraseMinimumWords * Defaults.consecutiveRepeatedPhraseMinimumCount else {
            return nil
        }

        let maximumWindowSize = min(Defaults.consecutiveRepeatedPhraseMaximumWords, words.count / Defaults.consecutiveRepeatedPhraseMinimumCount)
        guard maximumWindowSize >= Defaults.consecutiveRepeatedPhraseMinimumWords else {
            return nil
        }

        for windowSize in Defaults.consecutiveRepeatedPhraseMinimumWords...maximumWindowSize {
            var index = 0
            while index + windowSize * Defaults.consecutiveRepeatedPhraseMinimumCount <= words.count {
                let phrase = Array(words[index..<(index + windowSize)])
                var repetitionCount = 1
                var nextIndex = index + windowSize

                while nextIndex + windowSize <= words.count,
                      Array(words[nextIndex..<(nextIndex + windowSize)]) == phrase {
                    repetitionCount += 1
                    nextIndex += windowSize
                }

                if repetitionCount >= Defaults.consecutiveRepeatedPhraseMinimumCount {
                    return phrase.joined(separator: " ")
                }

                index += 1
            }
        }

        return nil
    }

    private func containsUnexpectedCJKScript(_ transcript: String) -> Bool {
        var cjkScalarCount = 0
        var letterScalarCount = 0
        var latinScalarCount = 0

        for scalar in transcript.unicodeScalars {
            guard CharacterSet.letters.contains(scalar) else {
                continue
            }

            letterScalarCount += 1
            if Self.isCJKScalar(scalar) {
                cjkScalarCount += 1
            } else if Self.isLatinScalar(scalar) {
                latinScalarCount += 1
            }
        }

        guard letterScalarCount > 0 else {
            return false
        }

        if latinScalarCount >= Defaults.likelyEnglishMinimumLatinScalars,
           cjkScalarCount >= Defaults.unexpectedScriptMinimumScalarsInLikelyEnglish {
            return true
        }

        guard cjkScalarCount >= Defaults.unexpectedScriptMinimumScalars else {
            return false
        }

        return Double(cjkScalarCount) / Double(letterScalarCount) >= Defaults.unexpectedScriptMinimumRatio
    }

    private static func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private static func isLatinScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F:
            return true
        default:
            return false
        }
    }

    private func boilerplateHallucination(in transcript: String) -> String? {
        let normalized = transcript
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        let boilerplatePhrases = [
            "thanks for watching",
            "thank you for watching",
            "like and subscribe",
            "dont forget to subscribe",
            "don't forget to subscribe",
            "please subscribe",
            "this is the end",
            "subtitles by",
            "transcribed by",
            "captions by"
        ]

        if let matchedPhrase = boilerplatePhrases.first(where: { normalized.contains($0) }) {
            return matchedPhrase
        }

        guard likelyLowInformationBoilerplate(transcript) else {
            return nil
        }

        return "low-information transcript"
    }

    private func likelyLowInformationBoilerplate(_ transcript: String) -> Bool {
        var latinScalarCount = 0
        var cjkScalarCount = 0
        for scalar in transcript.unicodeScalars where CharacterSet.letters.contains(scalar) {
            if Self.isLatinScalar(scalar) {
                latinScalarCount += 1
            } else if Self.isCJKScalar(scalar) {
                cjkScalarCount += 1
            }
        }

        guard latinScalarCount >= Defaults.boilerplateMinimumLatinScalars,
              cjkScalarCount == 0 else {
            return false
        }

        let words = transcript
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !words.isEmpty,
              words.count <= Defaults.boilerplateMaximumUsefulWords else {
            return false
        }

        let usefulWords = words.filter { !Self.boilerplateStopWords.contains($0) }
        return usefulWords.isEmpty
    }

    private static let boilerplateStopWords: Set<String> = [
        "a",
        "an",
        "and",
        "are",
        "end",
        "for",
        "from",
        "i",
        "in",
        "is",
        "it",
        "of",
        "on",
        "or",
        "so",
        "that",
        "the",
        "this",
        "to",
        "was",
        "we",
        "you"
    ]

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
