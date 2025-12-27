import Foundation

/// Represents a message from the assistant, which can contain text content, tool calls, or both.
public struct Message: Codable, Sendable {
    /// The textual content of the message, if any.
    public let content: String?
    
    /// The tool calls requested by the model, if any.
    public let toolCalls: [ToolCall]

    /// A representation of a tool call requested by the language model.
    public struct ToolCall: Codable, Sendable {
        /// A unique identifier for this specific tool call.
        public let id: String
        /// The name of the function to be called.
        public let name: String
        /// A JSON string containing the arguments for the function.
        public let arguments: String
    }
    
    public init(content: String?, toolCalls: [ToolCall]) {
        self.content = content
        self.toolCalls = toolCalls
    }
}
