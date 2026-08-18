import Foundation
import FoundationModels

@available(anyAppleOS 27.0, *)
public struct OpenAILanguageModel: Sendable {
    public let model: OpenAIModel
    public let baseURL: URL
    public let timeout: TimeInterval
    let authMode: AuthMode

    public init(
        name: OpenAIModel,
        auth: AuthMode,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        timeout: TimeInterval = 60
    ) {
        self.model = name
        self.authMode = auth
        self.baseURL = baseURL
        self.timeout = timeout
    }
}

@available(anyAppleOS 27.0, *)
extension OpenAILanguageModel: LanguageModel {
    public typealias Executor = OpenAIExecutor

    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.toolCalling, .vision, .reasoning, .guidedGeneration])
    }

    public var executorConfiguration: OpenAIExecutor.Configuration {
        .init(model: model, baseURL: baseURL, authMode: authMode, timeout: timeout)
    }
}

public struct OpenAIModel: Identifiable, Hashable, Sendable {
    public let id: String
    let alias: String?
    let reasoning: [String]
    let inputPrice: String
    let outputPrice: String
    let maxOutput: String
    let contextWindow: String
    let released: String
    let tools: [String]
}

extension OpenAIModel {
    public static let gpt5_6_sol = OpenAIModel(
        id: "gpt-5.6-sol",
        alias: "gpt-5.6",
        reasoning: ["none", "low", "medium", "high", "xhigh", "max"],
        inputPrice: "$5 / Input MTok",
        outputPrice: "$30 / Output MTok",
        maxOutput: "128K tokens",
        contextWindow: "1.05M",
        released: "Feb 16, 2026",
        tools: ["Functions", "Web search", "File search", "Computer use"]
    )
    
    public static let gpt5_6_terra = OpenAIModel(
        id: "gpt-5.6-terra",
        alias: nil,
        reasoning: ["none", "low", "medium", "high", "xhigh", "max"],
        inputPrice: "$2 / Input MTok",
        outputPrice: "$12 / Output MTok",
        maxOutput: "128K tokens",
        contextWindow: "1.05M",
        released: "Feb 16, 2026",
        tools: ["Functions", "Web search", "File search", "Computer use"]
    )
    
    public static let gpt5_6_luna = OpenAIModel(
        id: "gpt-5.6-luna",
        alias: nil,
        reasoning: ["none", "low", "medium", "high", "xhigh", "max"],
        inputPrice: "$0.20 / Input MTok",
        outputPrice: "$1.20 / Output MTok",
        maxOutput: "128K tokens",
        contextWindow: "1.05M",
        released: "Feb 16, 2026",
        tools: ["Functions", "Web search", "File search", "Computer use"]
    )
}
