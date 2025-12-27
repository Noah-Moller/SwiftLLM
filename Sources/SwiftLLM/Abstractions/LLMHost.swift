import Foundation

/// Describes the host and authentication for an OpenAI-compatible LLM provider.
public enum LLMHost: Sendable {
    /// A locally running server (e.g., Vapor, SwiftLLM) with no API key.
    case local(baseURL: URL, defaultModel: String? = nil)
    
    /// An external service requiring an API key (e.g., OpenAI, Groq, Together).
    case external(baseURL: URL, apiKey: String, defaultModel: String?)
    
    /// Computed properties to access host details.
    public var baseURL: URL {
        switch self {
        case .local(let baseURL, _):
            return baseURL
        case .external(let baseURL, _, _):
            return baseURL
        }
    }
    
    public var apiKey: String? {
        switch self {
        case .local:
            return nil
        case .external(_, let apiKey, _):
            return apiKey
        }
    }
    
    public var defaultModel: String? {
        switch self {
        case .local(_, let defaultModel):
            return defaultModel
        case .external(_, _, let defaultModel):
            return defaultModel
        }
    }
}
