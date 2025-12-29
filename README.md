# SwiftLLM

<p align="center">
    <img src="https://img.shields.io/badge/platforms-macOS%20%7C%20iOS-lightgrey.svg" alt="Platforms">
    <img src="https://img.shields.io/badge/Swift-5.7%2B-orange.svg" alt="Swift 5.7+">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License">
</p>

SwiftLLM is a lightweight, production-ready Swift library for working with Large Language Models (LLMs). Built by **Tetrix Technologies**, it provides a backend‑agnostic API modeled after Apple’s Foundation Models, so you can use the same friendly Swift interface with any OpenAI‑compatible provider—local or remote.

Use SwiftLLM across iOS and macOS for text generation, structured output, and tool calling with clean `async/await` APIs.

## Highlights

- **Familiar API**: Foundation Models–style interface with Swift-native ergonomics.
- **Provider-agnostic**: Connect to any OpenAI-compatible backend via `LLMHost`.
- **Structured output**: Decode directly into your `Codable` types.
- **Tool calling**: Register Swift tools; the session orchestrates calls automatically.
- **State handled for you**: `UniversalLanguageModelSession` manages history and tool loops.
- **Multi-platform**: iOS and macOS support out of the box.

## Requirements

- Swift 5.7+
- macOS 12.0+
- iOS 15.0+

## Installation

For host, add SwiftLLM to your `Package.swift`:

```swift
.package(url: "https://github.com/your-repo/SwiftLLM.git", from: "1.0.0")
```

Then include it in your target:

```swift
.target(
    name: "MyApp",
    dependencies: ["SwiftLLM"]
)
```

For client, add the package dependency using the Swift Package Manger in Xcode.

## Quick Start

### 1) Configure a host and model

```swift
import SwiftLLM

let host = LLMHost.external(
    baseURL: URL(string: "https://api.openai.com/v1")!,
    apiKey: "YOUR_API_KEY",
    defaultModel: "gpt-4o"
)

let llm = UniversalLanguageModel(client: .init(host: host))
```

### 2) Generate text

```swift
let session = llm.makeSession(instructions: "You are a helpful and concise assistant.")

do {
    let response = try await session.respond(to: "Hello! What is the capital of France?")
    print("Model:", response) // "Paris."
} catch {
    print("Error:", error)
}
```

### 3) Multi-turn conversation

```swift
let response2 = try await session.respond(to: "And what is its population?")
print("Model:", response2)

for entry in session.transcript.entries {
    switch entry {
    case .prompt(let text): print("User:", text)
    case .response(let text): print("AI:", text)
    default: break
    }
}
```

### 4) Structured output (`Codable`)

```swift
struct CatProfile: Codable {
    var name: String
    var age: Int
    var personality: String
}

let catSession = llm.makeSession(instructions: "Generate profiles for fictional rescue cats.")

do {
    let cat = try await catSession.respond(
        to: "Generate a profile for a playful orange tabby.",
        generating: CatProfile.self
    )
    print("\(cat.name) — \(cat.age), \(cat.personality)")
} catch {
    print("Error:", error)
}
```

### 5) Tool calling

```swift
struct WeatherTool: LLMTool {
    struct Arguments: Codable { let city: String }

    let name = "get_current_weather"
    let description = "Gets the current weather for a specified city."

    func call(arguments: Arguments) async throws -> String {
        // In a real app, call a weather API here.
        return "The weather in \(arguments.city) is 15°C and partly cloudy."
    }
}

let toolSession = llm.makeSession(tools: [WeatherTool()])

do {
    let response = try await toolSession.respond(to: "What's the weather like in London?")
    print("Final Response:", response)
} catch {
    print("Error:", error)
}
```

## Notes on Production Use

- Prefer server-side API key management; `LLMHost` supports external hosts and secure configuration.
- Any model implementing the OpenAI API spec works with SwiftLLM.
- Sessions are stateful; reuse them for multi-turn conversations and tool orchestration.

## License

MIT — see [LICENSE](LICENSE).

---

A project by **Tetrix Technologies**.
