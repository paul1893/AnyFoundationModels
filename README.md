# AnyFoundationModels

A lightweight, unified Swift package that conforms third-party AI providers (OpenAI, Anthropic, Google Gemini) to Apple's `LanguageModel` protocol.

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20visionOS-blue.svg)]()
[![SPM Compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 💡 Why This Package?

With Apple's introduction of the `LanguageModel` protocol at WWDC26 in Foundation Models, developers can interact with AI providers through a single, standardized interface. However, existing provider integrations often fall short in many ways:

| Provider | Existing official Swift Package | AnyFoundationModels |
| :--- | :--- | :--- |
| **OpenAI** | ❌ — No official solution proposed by OpenAI yet | ✅ |
| **Anthropic** | ✅ — BUT minimum version requirement is set to 27.0.<br/>Official package enforce min version OS 27, which makes it barely unusable in real project that have min version lower than that. | ✅ – minimum version requirement is set to `.iOS(.v18), .macOS(.v15), .visionOS(.v2), .watchOS(.v11)`<br/>Thanks to [@marcomasser](https://github.com/anthropics/ClaudeForFoundationModels/issues/12) for the `older-OS` branch. |
| **Google Gemini** | ✅ — BUT heavy. <br/>1. Add Firebase Swift package in your project<br/>2. Setup a Firebase project on `console.firebase.google.com`<br/>3. Add `GoogleService-Info.plist` and so on.<br/>…<br/>[Official tutorial](https://firebase.google.com/docs/ai-logic/apple-foundation-models-framework/get-started?api=dev) | ✅ — No Firebase configuration needed. |

---

## 📦 Installation

Add **AnyFoundationModels** to your project using Swift Package Manager:

### In Xcode:
1. Select `File` > `Add Package Dependencies...`
2. Enter the repository URL: `https://github.com/paul1893/AnyFoundationModels.git`

### In `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/paul1893/AnyFoundationModels.git", from: "1.0.0")
]
```

⚠️ Point to `branch: "master"` instead of 1.0.0 while Anthropic have not yet merged [@marcomasser pull request](https://github.com/anthropics/ClaudeForFoundationModels/issues/12) into their main branch.

## 🚀 Usage
Switch seamlessly between on-device models, Private Cloud Compute, OpenAI, Anthropic, and Google Gemini models using a single dynamic type:

```swift
import FoundationModels
import AnyFoundationModels

// Apple On-device
var model: any LanguageModel = SystemLanguageModel.default

// OR Apple Private Cloud Compute
model = PrivateCloudComputeLanguageModel()

// OR OpenAI GPT
model = OpenAILanguageModel(
    name: .gpt5_6_sol,
    auth: .apiKey("YOUR_OPENAI_API_KEY")
)

// OR Anthropic Claude
model = ClaudeLanguageModel(
    name: .sonnet5,
    auth: .apiKey("YOUR_ANTHROPIC_API_KEY")
)

// OR Google Gemini
model = GoogleLanguageModel(
    name: .gemini3_5_flash,
    auth: .apiKey("YOUR_GEMINI_API_KEY")
)

// Generate response using the LanguageModel interface
let session = LanguageModelSession(model: model)
let response = try await session.respond(to: "Explain quantum computing in one sentence.")
```