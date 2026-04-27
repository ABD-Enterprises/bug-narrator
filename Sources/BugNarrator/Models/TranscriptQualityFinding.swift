import Foundation

struct TranscriptQualityFinding: Codable, Equatable, Identifiable, Sendable {
    enum Severity: String, Codable, Sendable {
        case warning
        case error
    }

    enum Kind: String, Codable, Sendable {
        case repeatedText
        case abruptEnding
        case shortTranscript
    }

    let kind: Kind
    let severity: Severity
    let message: String

    var id: String {
        "\(kind.rawValue)-\(severity.rawValue)-\(message)"
    }

    init(kind: Kind, severity: Severity, message: String) {
        self.kind = kind
        self.severity = severity
        self.message = message
    }
}
