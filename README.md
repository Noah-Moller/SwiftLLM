# SwiftLLM

<p align="center">
    <img src="https://img.shields.io/badge/platforms-macOS%20%7C%20iOS-lightgrey.svg" alt="Platforms">
    <img src="https://img.shields.io/badge/Swift-5.7%2B-orange.svg" alt="Swift 5.7+">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License">
</p>

SwiftLLM is a powerful and elegant Swift library designed to simplify interaction with Large Language Models (LLMs). Developed by **Tetrix Technologies**, it provides a backend-agnostic API modeled after Apple's `LanguageModel` framework, allowing developers to work with any OpenAI-compatible provider.

Whether you're building an iOS app or a server-side Swift application, SwiftLLM provides a unified, modern, and Swift-native interface for text generation, structured output, and tool calling.

## Features

- **Familiar API**: A clean, `async/await` API inspired by Apple's Foundation Models.
- **Provider Agnostic**: Connect to any OpenAI-compatible backend (local or remote) via a simple `LLMHost` configuration.
- **Structured Output**: Decode model responses directly into your `Codable` Swift types.
- **Tool Calling**: Define native Swift tools that the model can call to perform actions and retrieve information.
- **Automatic State Management**: `UniversalLanguageModelSession` automatically manages conversation history and tool-calling loops.
- **Multi-Platform**: Works on both iOS and macOS.

## Requirements

- Swift 5.7+
- macOS 12.0+
- iOS 15.0+

## Installation

Add SwiftLLM as a dependency to your `Package.swift` file:

```swift
.package(url: "https://github.com/your-repo/SwiftLLM.git", from: "1.0.0")
```

And add it to your target's dependencies:

```swift
.target(
    name: "MyApp",
    dependencies: ["SwiftLLM"]),
```

## Usage

### 1. Initialisation

First, configure a `LLMHost` for your desired backend and create a `UniversalLanguageModel` instance.

```swift
import SwiftLLM

// Configure the host (e.g., OpenAI)
let host = LLMHost.external(
    baseURL: URL(string: "https://api.openai.com/v1")!,
    apiKey: "YOUR_API_KEY",
    defaultModel: "gpt-4o"
)

// Create the main model entry point
let llm = UniversalLanguageModel(client: .init(host: host))
```

### 2. Basic Text Generation

Create a session and generate a simple text response.

```swift
// Create a session with instructions
let session = llm.makeSession(instructions: "You are a helpful and concise assistant.")

do {
    // Get a simple string response
    let response = try await session.respond(to: "Hello! What is the capital of France?")
    print("Model:", response)
    // "Model: The capital of France is Paris."
} catch {
    print("Error:", error)
}
```

### 3. Multi-Turn Conversation & Transcript

The session object automatically maintains the conversation history.

```swift
// Continuing the same session from above...
let response2 = try await session.respond(to: "And what is its population?")
print("Model:", response2)
// "Model: The population of Paris is over 2 million people."

// You can inspect the full transcript at any time
for entry in session.transcript.entries {
    switch entry {
    case .prompt(let text): print("User: \(text)")
    case .response(let text): print("AI: \(text)")
    default: break
    }
}
```

### 4. Structured Output (Codable)

Generate structured data directly into your custom Swift `Codable` types.

```swift
// 1. Define your Codable struct
struct CatProfile: Codable {
    var name: String
    var age: Int
    var personality: String
}

// 2. Create a session
let catSession = llm.makeSession(instructions: "Generate profiles for fictional rescue cats.")

// 3. Generate the object
do {
    let cat = try await catSession.respond(
        to: "Generate a profile for a playful orange tabby.",
        generating: CatProfile.self
    )
    print("\(cat.name) is a \(cat.age)-year-old cat who is known for being \(cat.personality).")
    // "Felix is a 3-year-old cat who is known for being very playful and energetic."
} catch {
    print("Error:", error)
}
```

### 5. Tool Calling

Define native Swift tools that the model can use to answer questions. The framework handles the entire tool-calling loop automatically.

```swift
// 1. Define a tool
struct WeatherTool: LLMTool {
    struct Arguments: Codable {
        let city: String
    }
    
    let name = "get_current_weather"
    let description = "Gets the current weather for a specified city."
    
    func call(arguments: Arguments) async throws -> String {
        print("Tool called: Getting weather for \(arguments.city)...")
        // In a real app, this would call a weather API.
        return "The weather in \(arguments.city) is 15°C and partly cloudy."
    }
}

// 2. Create a session with the tool
let toolSession = llm.makeSession(tools: [WeatherTool()])

// 3. Ask a question that requires the tool
do {
    let response = try await toolSession.respond(to: "What's the weather like in London?")
    print("Final Response:", response)
    // "Final Response: The current weather in London is 15°C and partly cloudy."
} catch {
    print("Error:", error)
}
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

*A project by Tetrix Technologies.*
