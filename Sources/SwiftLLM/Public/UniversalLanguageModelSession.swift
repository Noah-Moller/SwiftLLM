import Combine
import Foundation

/// Represents a single, stateful conversation with a language model.
/// It manages the conversation history (transcript) and handles tool-calling loops automatically.
@MainActor
public final class UniversalLanguageModelSession: ObservableObject {
    private let client: LLMClient
    private var tools: [String: any LLMTool] = [:]
    private let jsonDecoder = JSONDecoder()

    /// The conversation history, published for UI updates.
    @Published public private(set) var transcript: Transcript

    public init(client: LLMClient, instructions: Instructions?, tools: [any LLMTool]) {
        self.client = client
        self.transcript = Transcript(instructions: instructions)
        for tool in tools {
            self.tools[tool.name] = tool
        }
    }

    // MARK: Core API Methods

    public func respond(
        to prompt: Prompt,
        options: GenerationOptions = .init()
    ) async throws -> String {
        transcript.entries.append(.prompt(prompt))
        
        let response = try await runCompletion(options: options)
        
        guard let content = response.content else {
            throw GenerationError.unexpectedResponse("Response contained no text content.")
        }
        
        transcript.entries.append(.response(Message(from: response)))
        return content
    }

    public func respond<T: Codable>(
        to prompt: Prompt,
        generating: T.Type,
        options: GenerationOptions = .init()
    ) async throws -> T {
        transcript.entries.append(.prompt(prompt))
        
        let response = try await runCompletion(options: options, responseFormat: .init(type: "json_object"))
        
        transcript.entries.append(.response(Message(from: response)))
        
        guard let jsonString = response.content else {
            throw GenerationError.unexpectedResponse("Response contained no JSON content.")
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw GenerationError.decodingFailed("Failed to convert response string to data.")
        }
        
        do {
            return try jsonDecoder.decode(T.self, from: jsonData)
        } catch {
            transcript.entries.append(.error(error))
            throw GenerationError.decodingFailed("Failed to decode JSON into \(T.self): \(error.localizedDescription)")
        }
    }
    
    // MARK: Internal Logic
    
    private func runCompletion(options: GenerationOptions, responseFormat: OpenAI.ResponseFormat? = nil) async throws -> OpenAI.ChatMessage {
        while true {
            let messages = await buildChatMessages(responseFormat: responseFormat)
            let toolDefs = try tools.isEmpty ? nil : tools.values.map { try $0.toOpenAIToolDefinition() }
            
            let request = OpenAI.ChatCompletionRequest(
                model: options.model ?? client.host.defaultModel ?? "default",
                messages: messages,
                tools: toolDefs,
                tool_choice: toolDefs != nil ? "auto" : nil,
                response_format: responseFormat,
                temperature: options.temperature,
                max_tokens: options.maxTokens
            )
            
            let response = try await client.performChatCompletion(request: request)
            
            guard let choice = response.choices.first else {
                throw GenerationError.unexpectedResponse("No choices returned from the model.")
            }
            
            let message = choice.message
            if let toolCalls = message.tool_calls, !toolCalls.isEmpty {
                transcript.entries.append(.response(Message(from: message)))
                for toolCall in toolCalls {
                    try await handleToolCall(toolCall)
                }
                continue
            }
            
            return message
        }
    }
    
    private func handleToolCall(_ toolCall: OpenAI.ToolCall) async throws {
        guard let tool = tools[toolCall.function.name] else {
            let error = ToolError.toolNotFound(toolCall.function.name)
            transcript.entries.append(.error(error))
            throw error
        }
        
        do {
            let output = try await tool.call(jsonArguments: toolCall.function.arguments)
            
            // Always JSON-encode the output to ensure the content is a valid JSON string.
            let outputData = try JSONEncoder().encode(output)
            let outputString = String(data: outputData, encoding: .utf8) ?? ""
            
            transcript.entries.append(.toolResult(id: toolCall.id, name: toolCall.function.name, output: outputString))
        } catch {
            let toolError = ToolError.executionFailed("Tool '\(toolCall.function.name)' failed: \(error.localizedDescription)")
            transcript.entries.append(.error(toolError))
            // Inform the model that the tool call failed.
            transcript.entries.append(.toolResult(id: toolCall.id, name: toolCall.function.name, output: "{\"error\": \"\(toolError.localizedDescription)\"}"))
        }
    }

    private func buildChatMessages(responseFormat: OpenAI.ResponseFormat? = nil) async -> [OpenAI.ChatMessage] {
        var messages: [OpenAI.ChatMessage] = []
        
        for entry in transcript.entries {
            switch entry {
            case .instructions(let text):
                messages.append(.init(role: "system", content: text))
            case .prompt(let text):
                messages.append(.init(role: "user", content: text))
            case .response(let message):
                messages.append(OpenAI.ChatMessage(from: message))
            case .toolResult(let id, _, let output):
                messages.append(.init(role: "tool", content: output, tool_call_id: id))
            case .error:
                break
            }
        }
        
        if responseFormat?.type == "json_object" {
            let jsonInstruction = "You are a helpful assistant designed to output JSON."
            if let systemMessageIndex = messages.firstIndex(where: { $0.role == "system" }) {
                var systemMessage = messages[systemMessageIndex]
                if !(systemMessage.content?.lowercased().contains("json") ?? false) {
                    systemMessage.content = (systemMessage.content ?? "") + " " + jsonInstruction
                    messages[systemMessageIndex] = systemMessage
                }
            } else {
                messages.insert(.init(role: "system", content: jsonInstruction), at: 0)
            }
        }
        
        return messages
    }
}

// MARK: - Mappers

private extension Message {
    init(from openAIChatMessage: OpenAI.ChatMessage) {
        self.content = openAIChatMessage.content
        self.toolCalls = (openAIChatMessage.tool_calls ?? []).map {
            Message.ToolCall(
                id: $0.id,
                name: $0.function.name,
                arguments: $0.function.arguments
            )
        }
    }
}

private extension OpenAI.ChatMessage {
    init(from message: Message) {
        self.role = "assistant"
        self.content = message.content
        self.tool_call_id = nil
        
        if !message.toolCalls.isEmpty {
            self.tool_calls = message.toolCalls.map {
                OpenAI.ToolCall(
                    id: $0.id,
                    type: "function",
                    function: .init(name: $0.name, arguments: $0.arguments)
                )
            }
        } else {
            self.tool_calls = nil
        }
    }
}

// MARK: - Errors
public enum GenerationError: Error, LocalizedError {
    case unexpectedResponse(String)
    case decodingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .unexpectedResponse(let reason): return "The model returned an unexpected response: \(reason)"
        case .decodingFailed(let reason): return "Failed to decode the model's response: \(reason)"
        }
    }
}

public enum ToolError: Error, LocalizedError {
    case toolNotFound(String)
    case argumentDecodingFailed(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name): return "The model tried to call a tool named '\(name)' which is not registered."
        case .argumentDecodingFailed(let reason): return "Failed to decode arguments for a tool call: \(reason)"
        case .executionFailed(let reason): return "The tool failed during execution: \(reason)"
        }
    }
}

// MARK: - Tool Extension Helper
extension LLMTool {
    func call(jsonArguments: String) async throws -> any Codable {
        guard let argumentsData = jsonArguments.data(using: .utf8) else {
            throw ToolError.argumentDecodingFailed("Invalid UTF-8 string for arguments.")
        }
        do {
            let typedArguments = try JSONDecoder().decode(Arguments.self, from: argumentsData)
            return try await self.call(arguments: typedArguments)
        } catch {
            throw ToolError.argumentDecodingFailed("JSON decoding error for \(Arguments.self): \(error.localizedDescription)")
        }
    }
    
    func toOpenAIToolDefinition() throws -> OpenAI.ToolDefinition {
        let schema = try JSONSchemaGenerator.generateSchema(for: Arguments.self)
        let function = OpenAI.Function(name: self.name, description: self.description, parameters: schema)
        return OpenAI.ToolDefinition(function: function)
    }
}
