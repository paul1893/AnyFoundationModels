import Foundation
import FoundationModels

@available(anyAppleOS 27.0, *)
public struct GeminiExecutor: LanguageModelExecutor {
    public typealias Model = GeminiLanguageModel

    public struct Configuration: Hashable, Sendable {
        public let model: GeminiModel
        public let baseURL: URL
        public let authMode: GeminiAuthMode
        public let timeout: TimeInterval
        public let fixedThinkingBudget: Int?

        public init(
            model: GeminiModel,
            baseURL: URL,
            authMode: GeminiAuthMode,
            timeout: TimeInterval,
            fixedThinkingBudget: Int? = nil
        ) {
            self.model = model
            self.baseURL = baseURL
            self.authMode = authMode
            self.timeout = timeout
            self.fixedThinkingBudget = fixedThinkingBudget
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: GeminiLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        do {
            let body = try GeminiRequestBuilder.build(
                from: request,
                model: configuration.model,
                fixedThinkingBudget: configuration.fixedThinkingBudget
            )
            var translator = GeminiEventTranslator()
            for try await event in GeminiClient(
                baseURL: configuration.baseURL,
                auth: configuration.authMode,
                timeout: configuration.timeout
            ).stream(model: configuration.model.id, body: body) {
                try Task.checkCancellation()
                await translator.translate(event, into: channel)
            }
        } catch {
            throw GeminiErrorMapper.map(error)
        }
    }

    public func prewarm(model: GeminiLanguageModel, transcript: Transcript) {}
}

@available(anyAppleOS 27.0, *)
enum GeminiRequestBuilder {
    static func build(
        from request: LanguageModelExecutorGenerationRequest,
        model: GeminiModel,
        fixedThinkingBudget: Int?
    ) throws -> GeminiJSONValue {
        var contents: [GeminiJSONValue] = []
        var systemParts: [GeminiJSONValue] = []

        for entry in request.transcript {
            switch entry {
            case .instructions(let value):
                systemParts.append(contentsOf: parts(from: value.segments))
            case .prompt(let value):
                contents.append(content(role: "user", parts: parts(from: value.segments)))
            case .response(let value):
                contents.append(content(role: "model", parts: parts(from: value.segments)))
            case .reasoning:
                // Gemini thought parts are preserved by a later metadata record;
                // visible reasoning text is not replayed as ordinary text.
                break
            case .toolCalls(let calls):
                contents.append(content(role: "model", parts: calls.map { call in
                    replayedFunctionCallPart(for: call)
                }))
            case .toolOutput(let value):
                contents.append(content(role: "user", parts: [
                    .object([
                        "functionResponse": .object([
                            "id": .string(value.id),
                            "name": .string(value.toolName),
                            "response": .object(["content": .string(text(from: value.segments))]),
                        ])
                    ])
                ]))
            @unknown default:
                break
            }
        }

        var generationConfig: [String: GeminiJSONValue] = [:]
        if let maximum = request.generationOptions.maximumResponseTokens {
            generationConfig["maxOutputTokens"] = .number(Double(maximum))
        }
        generationConfig["temperature"] = .number(request.generationOptions.temperature)

        if let schema = request.schema {
            guard model.capabilities.structuredOutput else {
                throw LanguageModelError.unsupportedGenerationGuide(.init(
                    schemaName: nil,
                    debugDescription: "\(model.id) does not support Gemini structured output."
                ))
            }
            generationConfig["responseMimeType"] = .string("application/json")
            generationConfig["responseSchema"] = schemaValue(schema)
        }

        let budget = fixedThinkingBudget ?? thinkingBudget(for: request.contextOptions.reasoningLevel)
        if let budget, model.capabilities.reasoning {
            generationConfig["thinkingConfig"] = .object([
                "thinkingBudget": .number(Double(budget))
            ])
        }

        var body: [String: GeminiJSONValue] = [
            "contents": .array(contents),
            "generationConfig": .object(generationConfig),
        ]
        if !systemParts.isEmpty { body["systemInstruction"] = .object(["parts": .array(systemParts)]) }

        if !request.enabledToolDefinitions.isEmpty {
            guard model.capabilities.functionCalling else {
                throw GeminiError.api(
                    status: 400,
                    message: "\(model.id) does not support Gemini function calling.",
                    requestID: nil
                )
            }
            body["tools"] = .array([.object([
                "functionDeclarations": .array(request.enabledToolDefinitions.map(functionDeclaration))
            ])])
        }
        return .object(body)
    }

    private static func content(role: String, parts: [GeminiJSONValue]) -> GeminiJSONValue {
        .object(["role": .string(role), "parts": .array(parts)])
    }

    private static func parts(from segments: [Transcript.Segment]) -> [GeminiJSONValue] {
        segments.compactMap { segment in
            switch segment {
            case .text(let value) where !value.content.isEmpty:
                return .object(["text": .string(value.content)])
            case .structure(let value):
                return .object(["text": .string(GeminiJSONValue(value.content).jsonText)])
            default:
                return nil
            }
        }
    }

    private static func text(from segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment in
            switch segment {
            case .text(let value): value.content
            case .structure(let value): GeminiJSONValue(value.content).jsonText
            default: nil
            }
        }.joined()
    }

    private static func functionDeclaration(_ definition: Transcript.ToolDefinition) -> GeminiJSONValue {
        .object([
            "name": .string(definition.name),
            "description": .string(definition.description),
            "parameters": schemaValue(definition.parameters),
        ])
    }

    private static func thoughtSignature(from call: Transcript.ToolCall) -> GeminiJSONValue {
        guard let metadata = call.metadata[GeminiTurnRecord.metadataKey],
              case .string(let value) = metadata.kind,
              let json = try? JSONDecoder().decode(GeminiJSONValue.self, from: Data(value.utf8)),
              let signature = json["thoughtSignature"]
        else { return .null }
        return signature
    }

    private static func replayedFunctionCallPart(for call: Transcript.ToolCall) -> GeminiJSONValue {
        var part: [String: GeminiJSONValue] = [
            "functionCall": .object([
                "name": .string(call.toolName),
                "args": GeminiJSONValue(call.arguments),
                // The Foundation Models tool-call id carries the Gemini id.
                "id": .string(call.id),
            ])
        ]
        if let signature = thoughtSignature(from: call).stringValue {
            // Gemini places thoughtSignature on Part, beside functionCall.
            part["thoughtSignature"] = .string(signature)
        }
        return .object(part)
    }

    private static func schemaValue(_ schema: GenerationSchema) -> GeminiJSONValue {
        guard let data = try? JSONEncoder().encode(schema),
              let value = try? JSONDecoder().decode(GeminiJSONValue.self, from: data) else {
            return .object(["type": .string("OBJECT"), "properties": .object([:])])
        }
        return sanitize(value)
    }

    private static let allowedSchemaKeys: Set<String> = [
        "type", "properties", "required", "items", "enum", "format", "description",
        "anyOf", "allOf", "oneOf", "$ref", "$defs", "definitions",
    ]

    private static let schemaMapKeys: Set<String> = ["properties", "$defs", "definitions"]

    private static func sanitize(_ value: GeminiJSONValue) -> GeminiJSONValue {
        switch value {
        case .object(let object):
            var result: [String: GeminiJSONValue] = [:]
            for (key, value) in object where allowedSchemaKeys.contains(key) {
                if schemaMapKeys.contains(key), case .object(let entries) = value {
                    // Preserve user-defined property and definition names.
                    result[key] = .object(entries.mapValues(sanitize))
                } else {
                    result[key] = sanitize(value)
                }
            }
            if case .string(let type)? = result["type"] {
                let upper = type.uppercased()
                if ["OBJECT", "ARRAY", "STRING", "NUMBER", "INTEGER", "BOOLEAN"].contains(upper) {
                    result["type"] = .string(upper)
                }
            }
            return .object(result)
        case .array(let values): return .array(values.map(sanitize))
        default: return value
        }
    }

    private static func thinkingBudget(for level: ContextOptions.ReasoningLevel?) -> Int? {
        switch level {
        case .light: 512
        case .moderate: 2048
        case .deep: 8192
        case .custom(let value): Int(value)
        @unknown default: nil
        }
    }
}

@available(anyAppleOS 27.0, *)
struct GeminiEventTranslator: Sendable {
    private let responseEntryID = UUID().uuidString
    private let toolCallsEntryID = UUID().uuidString
    private var toolNames: [String: String] = [:]

    mutating func translate(
        _ event: GeminiJSONValue,
        into channel: LanguageModelExecutorGenerationChannel
    ) async {
        guard let parts = event["candidates"]?[0]?["content"]?["parts"] else { return }
        guard case .array(let parts) = parts else { return }

        for part in parts {
            if let text = part["text"]?.stringValue, !text.isEmpty {
                await channel.send(.response(entryID: responseEntryID, action: .appendText(
                    text, segmentID: responseEntryID, tokenCount: 1
                )))
            }
            if case .object(let call)? = part["functionCall"],
               let name = call["name"]?.stringValue {
                // Gemini supplies a stable id for each function call. It must
                // be returned in the matching functionResponse on the next
                // request, so never replace it with a local UUID.
                let id = call["id"]?.stringValue ?? UUID().uuidString
                toolNames[id] = name
                let args = call["args"]?.jsonText ?? "{}"
                // Open the call before appending its complete arguments. The
                // Foundation Models channel uses the opening event to create
                // the tool-call entry, including when Gemini sent all args in
                // one response part.
                await channel.send(.toolCalls(entryID: toolCallsEntryID, action: .toolCall(
                    id: id, name: name, action: .appendArguments("", tokenCount: 0)
                )))
                await channel.send(.toolCalls(entryID: toolCallsEntryID, action: .toolCall(
                    id: id, name: name, action: .appendArguments(args, tokenCount: 1)
                )))
                // thoughtSignature is a sibling of functionCall on Gemini Part.
                if let signature = part["thoughtSignature"]?.stringValue {
                    let metadata = GeminiTurnRecord.metadata(
                        id: id,
                        thoughtSignature: signature
                    )
                    await channel.send(.toolCalls(entryID: toolCallsEntryID, action: .toolCall(
                        id: id,
                        name: name,
                        action: .updateMetadata(metadata)
                    )))
                }
            }
        }
    }
}

@available(anyAppleOS 27.0, *)
enum GeminiErrorMapper {
    static func map(_ error: Error) -> Error {
        if error is GeminiError { return error }
        if let api = error as? GeminiAPIError {
            let message = api.localizedDescription.lowercased()
            if api.status == 429 || message.contains("quota") || message.contains("resource exhausted") {
                return LanguageModelError.rateLimited(.init(
                    resetDate: nil,
                    debugDescription: api.localizedDescription
                ))
            }
            if api.status == 400 && api.message.lowercased().contains("token") {
                return LanguageModelError.contextSizeExceeded(.init(contextSize: 0, tokenCount: 0, debugDescription: api.localizedDescription))
            }
            return GeminiError.api(status: api.status, message: api.message, requestID: api.requestID)
        }
        if let url = error as? URLError, url.code == .timedOut {
            return LanguageModelError.timeout(.init(debugDescription: url.localizedDescription))
        }
        return error
    }
}
