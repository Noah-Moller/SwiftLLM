import Foundation

// Using a namespace for internal models to avoid polluting the global namespace.
internal enum OpenAI {
    struct ChatCompletionRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let tools: [ToolDefinition]?
        let tool_choice: String? // "auto", "none", or specific tool
        let response_format: ResponseFormat?
        let temperature: Double?
        let max_tokens: Int?
    }

    struct ChatMessage: Codable {
        let role: String
        var content: String?
        var tool_calls: [ToolCall]?
        let tool_call_id: String?
        
        init(role: String, content: String?, tool_calls: [ToolCall]? = nil, tool_call_id: String? = nil) {
            self.role = role
            self.content = content
            self.tool_calls = tool_calls
            self.tool_call_id = tool_call_id
        }

        // Manual encoding to omit nil values for content and tool_calls
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            try container.encodeIfPresent(content, forKey: .content)
            try container.encodeIfPresent(tool_calls, forKey: .tool_calls)
            try container.encodeIfPresent(tool_call_id, forKey: .tool_call_id)
        }
    }

    struct ToolDefinition: Codable {
        let type: String
        let function: Function
        
        init(function: Function) {
            self.type = "function"
            self.function = function
        }
    }
    
    struct Function: Codable {
        let name: String
        let description: String
        let parameters: JSONSchema
    }

    struct ChatCompletionResponse: Codable {
        let choices: [Choice]
        // Add other response fields like `usage` if needed
    }
    
    struct Choice: Codable {
        let message: ChatMessage
        let finish_reason: String? // "stop", "tool_calls", "length", etc.
    }

    struct ToolCall: Codable {
        let id: String
        let type: String
        let function: FunctionCall
    }

    struct FunctionCall: Codable {
        let name: String
        let arguments: String // This is a JSON string that we'll decode separately.
    }

    struct ResponseFormat: Codable {
        let type: String // e.g., "json_object"
    }
    
    // A codable representation for JSON Schema that supports nesting.
    final class JSONSchema: Codable, @unchecked Sendable {
        var type: String
        var properties: [String: JSONSchema]?
        var required: [String]?
        var items: JSONSchema?
        var description: String?

        init(type: String, description: String? = nil, properties: [String : JSONSchema]? = nil, required: [String]? = nil, items: JSONSchema? = nil) {
            self.type = type
            self.description = description
            self.properties = properties
            self.required = required
            self.items = items
        }

        // Manual Codable conformance
        enum CodingKeys: String, CodingKey {
            case type, properties, required, items, description
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            properties = try container.decodeIfPresent([String: JSONSchema].self, forKey: .properties)
            required = try container.decodeIfPresent([String].self, forKey: .required)
            items = try container.decodeIfPresent(JSONSchema.self, forKey: .items)
            description = try container.decodeIfPresent(String.self, forKey: .description)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(properties, forKey: .properties)
            try container.encodeIfPresent(required, forKey: .required)
            try container.encodeIfPresent(items, forKey: .items)
            try container.encodeIfPresent(description, forKey: .description)
        }
    }
}
