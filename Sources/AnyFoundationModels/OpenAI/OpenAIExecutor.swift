import Foundation
import FoundationModels

@available(anyAppleOS 27.0, *)
public struct OpenAIExecutor: LanguageModelExecutor {
    public typealias Model = OpenAILanguageModel

    public struct Configuration: Hashable, Sendable {
        public let model: OpenAIModel
        public let baseURL: URL
        public let authMode: AuthMode
        public let timeout: TimeInterval

        public init(model: OpenAIModel, baseURL: URL, authMode: AuthMode, timeout: TimeInterval) {
            self.model = model
            self.baseURL = baseURL
            self.authMode = authMode
            self.timeout = timeout
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration) throws {
        self.configuration = configuration
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: OpenAILanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        do {
            let body = try OpenAIRequestBuilder.build(from: request, model: configuration.model)
            var translator = OpenAIEventTranslator()
            for try await event in OpenAIHTTPClient(
                baseURL: configuration.baseURL,
                auth: configuration.authMode,
                timeout: configuration.timeout
            ).stream(body) {
                try Task.checkCancellation()
                await translator.translate(event, into: channel)
            }
        } catch {
            throw OpenAIErrorMapper.map(error)
        }
    }

    public func prewarm(model: OpenAILanguageModel, transcript: Transcript) {}
}

@available(anyAppleOS 27.0, *)
enum OpenAIRequestBuilder {
    static func build(
        from request: LanguageModelExecutorGenerationRequest,
        model: OpenAIModel
    ) throws -> OpenAIResponseRequest {
        var instructions: [String] = []
        var input: [OpenAIJSONValue] = []

        for entry in request.transcript {
            switch entry {
            case .instructions(let value):
                instructions.append(value.segments.compactMap(text).joined(separator: "\n"))
            case .prompt(let value):
                input.append(message(role: "user", text: value.segments.compactMap(text).joined()))
            case .response(let value):
                input.append(message(role: "assistant", text: value.segments.compactMap(text).joined()))
            case .reasoning:
                break
            case .toolCalls(let value):
                for call in value {
                    input.append(.object([
                        "type": .string("function_call"),
                        "call_id": .string(call.id),
                        "name": .string(call.toolName),
                        "arguments": .string(OpenAIJSONValue(call.arguments).jsonText),
                    ]))
                }
            case .toolOutput(let value):
                input.append(.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(value.id),
                    "output": .string(value.segments.compactMap(text).joined()),
                ]))
            @unknown default:
                break
            }
        }

        var tools: [OpenAIJSONValue] = []
        for definition in request.enabledToolDefinitions {
            tools.append(.object([
                "type": .string("function"),
                "name": .string(definition.name),
                "description": .string(definition.description),
                "parameters": schema(definition.parameters),
                "strict": .bool(true),
            ]))
        }

        var body = OpenAIResponseRequest(
            model: model.id,
            input: input,
            instructions: instructions.isEmpty ? nil : instructions.joined(separator: "\n\n"),
            maxOutputTokens: request.generationOptions.maximumResponseTokens,
            tools: tools.isEmpty ? nil : tools
        )
        body.temperature = request.generationOptions.temperature
        body.reasoning = reasoning(request.contextOptions.reasoningLevel, model: model)
        if let generationSchema = request.schema {
            body.text = .object([
                "format": .object([
                    "type": .string("json_schema"),
                    "name": .string("generated_output"),
                    "strict": .bool(true),
                    "schema": schema(generationSchema),
                ])
            ])
        }
        return body
    }

    private static func message(role: String, text: String) -> OpenAIJSONValue {
        .object(["type": .string("message"), "role": .string(role), "content": .string(text)])
    }

    private static func text(_ segment: Transcript.Segment) -> String? {
        if case .text(let value) = segment { return value.content }
        if case .structure(let value) = segment { return value.content.jsonString }
        return nil
    }

    private static func schema(_ schema: GenerationSchema) -> OpenAIJSONValue {
        guard let data = try? JSONEncoder().encode(schema),
              let value = try? JSONDecoder().decode(OpenAIJSONValue.self, from: data) else {
            return .object(["type": .string("object"), "additionalProperties": .bool(false)])
        }
        return sanitize(value)
    }

    private static let allowedSchemaKeys: Set<String> = [
        "type", "properties", "required", "items", "enum", "const", "anyOf", "allOf", "oneOf",
        "$ref", "$defs", "definitions", "description", "format", "additionalProperties",
    ]

    private static func sanitize(_ value: OpenAIJSONValue) -> OpenAIJSONValue {
        switch value {
        case .object(let object):
            var result: [String: OpenAIJSONValue] = [:]
            for (key, value) in object where allowedSchemaKeys.contains(key) { result[key] = sanitize(value) }
            if result["type"]?.stringValue == "object", result["additionalProperties"] == nil {
                result["additionalProperties"] = .bool(false)
            }
            return .object(result)
        case .array(let array): return .array(array.map(sanitize))
        default: return value
        }
    }

    private static func reasoning(
        _ level: ContextOptions.ReasoningLevel?,
        model: OpenAIModel
    ) -> OpenAIJSONValue? {
        let value: String? = switch level {
        case .light: "low"
        case .moderate: "medium"
        case .deep: "high"
        case .custom(let value): value
        @unknown default: nil
        }
        guard let value, value != "none", model.reasoning.contains(value) else { return nil }
        return .object(["effort": .string(value)])
    }
}

@available(anyAppleOS 27.0, *)
struct OpenAIEventTranslator: Sendable {
    private var toolNames: [String: String] = [:]
    private var callIDs: [String: String] = [:]
    private var responseEntryID = UUID().uuidString
    private var toolEntryID = UUID().uuidString

    mutating func translate(
        _ event: OpenAIStreamEvent,
        into channel: LanguageModelExecutorGenerationChannel
    ) async {
        switch event.type {
        case "response.output_text.delta":
            if let delta = event.delta, !delta.isEmpty {
                await channel.send(.response(entryID: responseEntryID, action: .appendText(
                    delta, segmentID: responseEntryID, tokenCount: 1
                )))
            }
        case "response.output_item.added":
            guard let item = event.item, item["type"]?.stringValue == "function_call",
                  let id = item["call_id"]?.stringValue ?? item["id"]?.stringValue,
                  let name = item["name"]?.stringValue else { return }
            let itemID = item["id"]?.stringValue ?? id
            toolNames[id] = name
            callIDs[itemID] = id
            await channel.send(.toolCalls(entryID: toolEntryID, action: .toolCall(
                id: id, name: name, action: .appendArguments("", tokenCount: 1)
            )))
        case "response.function_call_arguments.delta":
            guard let delta = event.delta, let itemID = event.itemID else { return }
            let id = callIDs[itemID] ?? itemID
            await channel.send(.toolCalls(entryID: toolEntryID, action: .toolCall(
                id: id, name: toolNames[id] ?? "", action: .appendArguments(delta, tokenCount: 1)
            )))
        default:
            break
        }
    }
}

@available(anyAppleOS 27.0, *)
enum OpenAIErrorMapper {
    static func map(_ error: Error) -> Error {
        if error is OpenAIError { return error }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return LanguageModelError.timeout(.init(debugDescription: urlError.localizedDescription))
        }
        if let apiError = error as? OpenAIAPIError {
            if apiError.type == "insufficient_quota" || apiError.code == "credit_balance_exhausted" {
                return LanguageModelError.rateLimited(.init(
                    resetDate: nil,
                    debugDescription: apiError.localizedDescription
                ))
            }
            let text = apiError.localizedDescription.lowercased()
            if text.contains("rate limit") || text.contains("too many requests") {
                return LanguageModelError.rateLimited(.init(
                    resetDate: nil,
                    debugDescription: apiError.localizedDescription
                ))
            }
            if text.contains("context") || text.contains("token") {
                return LanguageModelError.contextSizeExceeded(.init(contextSize: 0, tokenCount: 0, debugDescription: apiError.localizedDescription))
            }
        }
        return error
    }
}

@available(anyAppleOS 27.0, *)
private extension OpenAIJSONValue {
    init(_ content: GeneratedContent) {
        switch content.kind {
        case .null: self = .null
        case .bool(let value): self = .bool(value)
        case .number(let value): self = .number(value)
        case .string(let value): self = .string(value)
        case .array(let values): self = .array(values.map(Self.init))
        case .structure(let properties, _): self = .object(properties.mapValues(Self.init))
        @unknown default: self = .null
        }
    }

    var jsonText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(self), as: UTF8.self)
    }
}
