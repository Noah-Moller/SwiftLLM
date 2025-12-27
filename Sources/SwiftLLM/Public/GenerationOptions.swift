/// High-level instructions that define a model's persona, style, or task.
public typealias Instructions = String

/// The user-provided input for the model to respond to.
public typealias Prompt = String

/// Options for configuring the generation process.
public struct GenerationOptions {
    /// Controls randomness. Lower values make the model more deterministic. (e.g., 0.8)
    public var temperature: Double?
    /// The maximum number of tokens to generate.
    public var maxTokens: Int?
    /// The name of the model to use for this specific request. Overrides the host's default.
    public var model: String?
    
    public init(temperature: Double? = nil, maxTokens: Int? = nil, model: String? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.model = model
    }
}
