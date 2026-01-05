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
        
        print("SwiftLLM: Starting structured output generation for \(T.self)")
        
        // Generate JSON schema for the type to include in prompt if needed
        let jsonSchema = try? JSONSchemaGenerator.generateSchema(for: T.self)
        
        let response = try await runCompletion(options: options, responseFormat: .init(type: "json_object"), jsonSchema: jsonSchema)
        
        transcript.entries.append(.response(Message(from: response)))
        
        guard let jsonString = response.content, !jsonString.isEmpty else {
            let errorMsg = "Response contained no JSON content. " +
                          "Content is nil: \(response.content == nil). " +
                          "Content length: \(response.content?.count ?? 0). " +
                          "Has tool calls: \(response.tool_calls != nil && !(response.tool_calls?.isEmpty ?? true))."
            print("SwiftLLM: \(errorMsg)")
            throw GenerationError.unexpectedResponse(errorMsg)
        }
        
        print("SwiftLLM: Received JSON content (\(jsonString.count) chars): \(jsonString.prefix(200))...")
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw GenerationError.decodingFailed("Failed to convert response string to data.")
        }
        
        do {
            let decoded = try jsonDecoder.decode(T.self, from: jsonData)
            print("SwiftLLM: Successfully decoded \(T.self)")
            return decoded
        } catch {
            transcript.entries.append(.error(error))
            print("SwiftLLM: Failed to decode JSON: \(error)")
            print("SwiftLLM: JSON content was: \(jsonString)")
            throw GenerationError.decodingFailed("Failed to decode JSON into \(T.self): \(error.localizedDescription)")
        }
    }
    
    // MARK: Internal Logic
    
    private func runCompletion(options: GenerationOptions, responseFormat: OpenAI.ResponseFormat? = nil, jsonSchema: OpenAI.JSONSchema? = nil) async throws -> OpenAI.ChatMessage {
        var toolsCompleted = false
        var toolsDisabled = false // Track if we've disabled tools due to empty response
        var responseFormatDisabled = false // Track if we've disabled response_format due to 400 error
        var iterationCount = 0
        let maxIterations = 10 // Prevent infinite loops
        
        while iterationCount < maxIterations {
            iterationCount += 1
            
            let toolDefs: [OpenAI.ToolDefinition]?
            
            // After tool calls complete, or if tools were disabled due to empty response, remove tools
            if toolsCompleted || toolsDisabled || tools.isEmpty {
                toolDefs = nil
            } else {
                toolDefs = try tools.values.map { try $0.toOpenAIToolDefinition() }
            }
            
            // JSON mode cannot be combined with tools - skip response_format when tools are present or disabled
            let effectiveResponseFormat = (toolDefs != nil || responseFormatDisabled) ? nil : responseFormat
            
            // Always include JSON schema in prompt when structured output is requested (whether using response_format or not)
            // This ensures the model knows the expected structure
            let messages = await buildChatMessages(responseFormat: effectiveResponseFormat, jsonSchema: jsonSchema)
            
            print("SwiftLLM: Iteration \(iterationCount) - Tools: \(toolDefs?.count ?? 0), ResponseFormat: \(effectiveResponseFormat != nil ? "json_object" : "none"), ToolsCompleted: \(toolsCompleted), ToolsDisabled: \(toolsDisabled), ResponseFormatDisabled: \(responseFormatDisabled)")
            print("SwiftLLM: Messages count: \(messages.count)")
            if let firstMessage = messages.first {
                print("SwiftLLM: First message role: \(firstMessage.role), content length: \(firstMessage.content?.count ?? 0)")
            }
            
            let request = OpenAI.ChatCompletionRequest(
                model: options.model ?? client.host.defaultModel ?? "default",
                messages: messages,
                tools: toolDefs,
                tool_choice: toolDefs != nil ? "auto" : nil,
                response_format: effectiveResponseFormat,
                temperature: options.temperature,
                max_tokens: options.maxTokens
            )
            
            let response: OpenAI.ChatCompletionResponse
            do {
                response = try await client.performChatCompletion(request: request)
            } catch let error as URLError where error.code == .badServerResponse {
                // Check if it's a 400 error related to response_format
                if effectiveResponseFormat != nil && !responseFormatDisabled {
                    print("SwiftLLM: 400 error when using response_format. Retrying without response_format, using JSON schema in prompt instead.")
                    responseFormatDisabled = true
                    continue
                }
                // If we've already disabled response_format and still get 400, something else is wrong
                print("SwiftLLM: 400 error persists even with response_format disabled. Error: \(error)")
                throw error
            } catch {
                throw error
            }
            
            guard let choice = response.choices.first else {
                throw GenerationError.unexpectedResponse("No choices returned from the model.")
            }
            
            let message = choice.message
            let finishReason = choice.finish_reason ?? "unknown"
            
            // Log for debugging - dump the message structure
            print("SwiftLLM: Iteration \(iterationCount) - Finish reason: \(finishReason)")
            print("SwiftLLM: Message content: \(message.content ?? "nil")")
            print("SwiftLLM: Message tool_calls: \(message.tool_calls?.count ?? 0)")
            if let toolCalls = message.tool_calls, !toolCalls.isEmpty {
                print("SwiftLLM: Tool call names: \(toolCalls.map { $0.function.name }.joined(separator: ", "))")
            }
            print("SwiftLLM: Message role: \(message.role)")
            print("SwiftLLM: Message tool_call_id: \(message.tool_call_id ?? "nil")")
            
            if let toolCalls = message.tool_calls, !toolCalls.isEmpty {
                print("SwiftLLM: Iteration \(iterationCount) - Model requested \(toolCalls.count) tool call(s)")
            } else if message.content != nil && !(message.content?.isEmpty ?? true) {
                print("SwiftLLM: Iteration \(iterationCount) - Received response with content (\(message.content?.count ?? 0) chars)")
            } else {
                print("SwiftLLM: Iteration \(iterationCount) - Response has no content and no tool calls (finish_reason: \(finishReason))")
                // If finish_reason is "length", the model hit max_tokens and couldn't complete
                if finishReason == "length" {
                    print("SwiftLLM: Warning - Model hit token limit. Consider increasing max_tokens.")
                }
            }
            
            if let toolCalls = message.tool_calls, !toolCalls.isEmpty {
                // If we already completed tool calls and they're requesting more, that's unexpected
                if toolsCompleted || toolsDisabled {
                    print("SwiftLLM: Model requested additional tool calls after tools were removed. This may indicate the model needs more context.")
                }
                
                transcript.entries.append(.response(Message(from: message)))
                for toolCall in toolCalls {
                    print("SwiftLLM: Executing tool '\(toolCall.function.name)'")
                    try await handleToolCall(toolCall)
                }
                toolsCompleted = true // Mark that we've completed tool calls
                continue
            }
            
            // If we reach here, we have a final response
            // Check if it's actually empty (including empty string)
            let hasContent = message.content != nil && !(message.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            
            if !hasContent {
                // This is an error - we got a response with no usable content
                // If tools were available and we got an empty response, this suggests the model doesn't support tools
                // Don't retry - just fail with a clear error
                if !toolsCompleted && !toolsDisabled && toolDefs != nil {
                    let errorMsg = "Model returned empty response when tools were available. This suggests the model may not support tool calling. " +
                                  "Try without tools or use a different model. " +
                                  "Finish reason: \(finishReason)."
                    print("SwiftLLM: \(errorMsg)")
                    throw GenerationError.unexpectedResponse(errorMsg)
                }
                
                let errorMsg = "Response contained no content after \(iterationCount) iteration(s). " +
                              "Has tool calls: \(message.tool_calls != nil && !(message.tool_calls?.isEmpty ?? true)). " +
                              "Tool calls completed: \(toolsCompleted). " +
                              "Tools disabled: \(toolsDisabled). " +
                              "Response format requested: \(responseFormat != nil). " +
                              "Finish reason: \(finishReason)."
                throw GenerationError.unexpectedResponse(errorMsg)
            }
            
            return message
        }
        
        throw GenerationError.unexpectedResponse("Exceeded maximum iterations (\(maxIterations)). The model may be stuck in a tool-calling loop.")
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

    private func buildChatMessages(responseFormat: OpenAI.ResponseFormat? = nil, jsonSchema: OpenAI.JSONSchema? = nil) async -> [OpenAI.ChatMessage] {
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
        
            // Always include JSON schema when provided, whether using response_format or not
            if let schema = jsonSchema {
            do {
                let schemaEncoder = JSONEncoder()
                schemaEncoder.outputFormatting = .prettyPrinted
                let schemaData = try schemaEncoder.encode(schema)
                if let schemaString = String(data: schemaData, encoding: .utf8) {
                    // When tools are disabled, clean up tool-related instructions
                    if let systemMessageIndex = messages.firstIndex(where: { $0.role == "system" }) {
                        var systemMessage = messages[systemMessageIndex]
                        var cleanedContent = systemMessage.content ?? ""
                        
                        // Remove tool usage section if present
                        if let toolUsageRange = cleanedContent.range(of: "TOOL USAGE:") {
                            // Find the end of the tool usage section (look for double newline or end of string)
                            if let endRange = cleanedContent.range(of: "\n\n", range: toolUsageRange.upperBound..<cleanedContent.endIndex) {
                                cleanedContent.removeSubrange(toolUsageRange.lowerBound..<endRange.upperBound)
                            } else {
                                // No double newline found, remove to end
                                cleanedContent.removeSubrange(toolUsageRange.lowerBound..<cleanedContent.endIndex)
                            }
                            // Clean up any trailing whitespace
                            cleanedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        
                        let jsonInstruction = """
                        You are a helpful assistant designed to output JSON. You must respond with valid JSON that matches the following schema:
                        \(schemaString)
                        """
                        systemMessage.content = cleanedContent + "\n\n" + jsonInstruction
                        messages[systemMessageIndex] = systemMessage
                    } else {
                        let jsonInstruction = """
                        You are a helpful assistant designed to output JSON. You must respond with valid JSON that matches the following schema:
                        \(schemaString)
                        """
                        messages.insert(.init(role: "system", content: jsonInstruction), at: 0)
                    }
                }
            } catch {
                print("SwiftLLM: Warning - Failed to encode JSON schema for prompt: \(error)")
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
