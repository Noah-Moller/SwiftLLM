import Foundation

/// A chronological record of a conversation with the language model.
public struct Transcript {
    public internal(set) var entries: [Entry] = []
    
    public init(instructions: Instructions?) {
        if let instructions {
            entries.append(.instructions(instructions))
        }
    }
    
    public enum Entry {
        case instructions(Instructions)
        case prompt(Prompt)
        /// An entire assistant message, which could be a text response or a tool call request.
        case response(Message)
        /// The output of a single tool call.
        case toolResult(id: String, name: String, output: String)
        case error(Error)
    }
}
