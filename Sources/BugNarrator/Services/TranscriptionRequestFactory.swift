import Foundation

struct TranscriptionRequestFactory {
    static let defaultAPIBaseURL = URL(string: "https://api.openai.com")!

    func validationRequest(
        apiKey: String,
        apiBaseURL: URL = Self.defaultAPIBaseURL
    ) -> URLRequest {
        var request = URLRequest(url: OpenAIEndpointBuilder.endpoint(for: "v1/models", baseURL: apiBaseURL))
        request.httpMethod = "GET"
        applyAuthorization(apiKey, to: &request)
        return request
    }

    func transcriptionRequest(
        apiKey: String,
        transcriptionRequest: TranscriptionRequest,
        boundary: String,
        body: Data
    ) -> URLRequest {
        var request = URLRequest(
            url: OpenAIEndpointBuilder.endpoint(
                for: "v1/audio/transcriptions",
                baseURL: transcriptionRequest.apiBaseURL
            )
        )
        request.httpMethod = "POST"
        applyAuthorization(apiKey, to: &request)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func applyAuthorization(_ apiKey: String, to request: inout URLRequest) {
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }
}
