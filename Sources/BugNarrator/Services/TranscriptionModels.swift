import Foundation

struct TranscriptionRequest: Sendable {
    static let remoteTimeout: TimeInterval = 180
    static let localParakeetTimeout: TimeInterval = 15 * 60

    let model: String
    let languageHint: String?
    let prompt: String?
    let apiBaseURL: URL
    let provider: AIProvider

    init(
        model: String,
        languageHint: String?,
        prompt: String?,
        apiBaseURL: URL = URL(string: "https://api.openai.com")!,
        provider: AIProvider = .openAI
    ) {
        self.model = model
        self.languageHint = languageHint
        self.prompt = prompt
        self.apiBaseURL = apiBaseURL
        self.provider = provider
    }

    var timeoutInterval: TimeInterval {
        provider == .parakeetLocal ? Self.localParakeetTimeout : Self.remoteTimeout
    }
}

struct TranscriptionResult: Sendable {
    let text: String
    let segments: [TranscriptionSegment]
    let qualityFindings: [TranscriptQualityFinding]

    init(
        text: String,
        segments: [TranscriptionSegment],
        qualityFindings: [TranscriptQualityFinding] = []
    ) {
        self.text = text
        self.segments = segments
        self.qualityFindings = qualityFindings
    }
}

struct TranscriptionSegment: Decodable, Sendable {
    let start: Double
    let end: Double
    let text: String
}
