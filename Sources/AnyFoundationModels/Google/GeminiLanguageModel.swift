import Foundation
import FoundationModels

/// Gemini as a Foundation Models server-side language model.
@available(anyAppleOS 27.0, *)
public struct GeminiLanguageModel: Sendable {
    public let model: GeminiModel
    public let baseURL: URL
    public let timeout: TimeInterval
    public let fixedThinkingBudget: Int?
    let authMode: GeminiAuthMode

    public init(
        name: GeminiModel,
        auth: GeminiAuthMode,
        fixedThinkingBudget: Int? = nil,
        baseURL: URL = GeminiLanguageModel.defaultBaseURL,
        timeout: TimeInterval = 60
    ) {
        precondition(fixedThinkingBudget == nil || fixedThinkingBudget ?? 0 >= 0)
        self.model = name
        self.authMode = auth
        self.fixedThinkingBudget = fixedThinkingBudget
        self.baseURL = baseURL
        self.timeout = timeout
    }

    public static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
}

@available(anyAppleOS 27.0, *)
extension GeminiLanguageModel: LanguageModel {
    public typealias Executor = GeminiExecutor

    public var capabilities: LanguageModelCapabilities {
        var values: [LanguageModelCapabilities.Capability] = [.toolCalling]
        if model.capabilities.imageInput { values.append(.vision) }
        if model.capabilities.reasoning { values.append(.reasoning) }
        if model.capabilities.structuredOutput { values.append(.guidedGeneration) }
        return LanguageModelCapabilities(values)
    }

    public var executorConfiguration: GeminiExecutor.Configuration {
        .init(
            model: model,
            baseURL: baseURL,
            authMode: authMode,
            timeout: timeout,
            fixedThinkingBudget: fixedThinkingBudget
        )
    }
}

public struct GeminiModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let capabilities: Capabilities

    public init(id: String, capabilities: Capabilities = .init()) {
        self.id = id
        self.capabilities = capabilities
    }

    public struct Capabilities: Hashable, Sendable {
        public var imageInput: Bool
        public var reasoning: Bool
        public var structuredOutput: Bool
        public var functionCalling: Bool

        public init(
            imageInput: Bool = true,
            reasoning: Bool = true,
            structuredOutput: Bool = true,
            functionCalling: Bool = true
        ) {
            self.imageInput = imageInput
            self.reasoning = reasoning
            self.structuredOutput = structuredOutput
            self.functionCalling = functionCalling
        }
    }
}

extension GeminiModel {
    public static let gemini3_1_pro = GeminiModel(id: "gemini-3.1-pro-preview")
    public static let gemini3_5_flash = GeminiModel(id: "gemini-3.5-flash")
    public static let gemini3_5_flash_lite = GeminiModel(id: "gemini-3.5-flash-lite")
    public static let gemini3_1_flash_lite = GeminiModel(id: "gemini-3.1-flash-lite")
}

/// Compatibility aliases for the original Google placeholder names.
@available(anyAppleOS 27.0, *)
public typealias GoogleLanguageModel = GeminiLanguageModel
public typealias GoogleModel = GeminiModel
