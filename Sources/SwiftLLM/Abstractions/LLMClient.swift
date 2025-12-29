import Foundation

/// The client responsible for communicating with the specified LLM host.
public final class LLMClient: Sendable {
    public let host: LLMHost

    private let urlSession: URLSession

    public init(host: LLMHost) {
        self.host = host
        self.urlSession = URLSession(configuration: .default)
    }

    /// Internal method to perform a chat completion request.
    internal func performChatCompletion(
        request: OpenAI.ChatCompletionRequest
    ) async throws -> OpenAI.ChatCompletionResponse {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted // For readable logs
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase

        var urlRequest = URLRequest(url: host.baseURL.appendingPathComponent("v1/chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = host.apiKey {
            urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let requestData = try jsonEncoder.encode(request)
        urlRequest.httpBody = requestData

        let (data, response) = try await urlSession.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            // Error is already printed from the response log above.
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned an error: \((response as? HTTPURLResponse)?.statusCode ?? -1). See console log for details."])
        }
        
        return try jsonDecoder.decode(OpenAI.ChatCompletionResponse.self, from: data)
    }
}
