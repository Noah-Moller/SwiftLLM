import Foundation

/// A provider-agnostic language model that can be configured to use various hosts.
/// It acts as the primary entry point for creating language model sessions.
public final class UniversalLanguageModel {
    private let client: LLMClient

    /// Initializes a model with a specific client configuration.
    public init(client: LLMClient) {
        self.client = client
    }

    /// Creates a new, independent session for interacting with the language model.
    /// - Parameters:
    ///   - instructions: Optional high-level instructions that define the model's role or behavior for the session.
    ///   - tools: An array of tools the model can use during the session.
    /// - Returns: A `UniversalLanguageModelSession` instance.
    @MainActor
    public func makeSession(
        instructions: Instructions? = nil,
        tools: [any LLMTool] = []
    ) -> UniversalLanguageModelSession {
        UniversalLanguageModelSession(client: client, instructions: instructions, tools: tools)
    }
}
