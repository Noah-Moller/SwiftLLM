import Foundation

/// A protocol for defining a tool that the language model can decide to call.
public protocol LLMTool: Sendable {
    /// The type of arguments this tool accepts, which must be `Codable`.
    associatedtype Arguments: Codable
    /// The type of output this tool produces, which must be `Codable`.
    associatedtype Output: Codable

    /// A unique name for the tool.
    var name: String { get }
    
    /// A description of what the tool does, used by the model to decide when to call it.
    var description: String { get }

    /// The function that executes the tool's logic.
    /// - Parameter arguments: The arguments decoded by the model.
    /// - Returns: The tool's output.
    func call(arguments: Arguments) async throws -> Output
}
