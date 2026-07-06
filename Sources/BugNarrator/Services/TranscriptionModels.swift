import Foundation

struct TranscriptionRequest: Sendable {
    let model: String
    let languageHint: String?
    let prompt: String?
    let apiBaseURL: URL

    init(
        model: String,
        languageHint: String?,
        prompt: String?,
        apiBaseURL: URL = URL(string: "https://api.openai.com")!
    ) {
        self.model = model
        self.languageHint = languageHint
        self.prompt = prompt
        self.apiBaseURL = apiBaseURL
    }
}

struct TranscriptionSegment: Decodable, Sendable {
    let start: Double
    let end: Double
    let text: String
}
