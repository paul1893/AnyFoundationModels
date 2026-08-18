import FoundationModels
import Testing

@testable import AnyFoundationModels

@available(anyAppleOS 27.0, *)
@Suite struct GeminiRequestBuilderTests {
    @Test func instructionsAndPromptBecomeGeminiContents() throws {
        let transcript = Transcript(entries: [
            .instructions(.init(segments: [.text(.init(content: "Be concise."))], toolDefinitions: [])),
            .prompt(.init(segments: [.text(.init(content: "Hello"))])),
        ])
        let body = try GeminiRequestBuilder.build(
            from: .make(transcript: transcript),
            model: .gemini3_1_pro,
            fixedThinkingBudget: nil
        )
        #expect(body["systemInstruction"]?["parts"]?[0]["text"] == .string("Be concise."))
        #expect(body["contents"]?[0]["role"] == .string("user"))
        #expect(body["contents"]?[0]["parts"]?[0]["text"] == .string("Hello"))
    }

    @Test func structuredOutputUsesGeminiJSONConfiguration() throws {
        @Generable struct Output { var city: String }
        let request = LanguageModelExecutorGenerationRequest.make(
            transcript: Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Plan"))]))]),
            schema: Output.generationSchema
        )
        let body = try GeminiRequestBuilder.build(
            from: request,
            model: .gemini3_1_pro,
            fixedThinkingBudget: nil
        )
        #expect(body["generationConfig"]?["responseMimeType"] == .string("application/json"))
        #expect(body["generationConfig"]?["responseSchema"]?["type"] == .string("OBJECT"))
    }

    @Test func toolsBecomeFunctionDeclarations() throws {
        let definition = Transcript.ToolDefinition(
            name: "weather",
            description: "Returns weather.",
            parameters: TestArguments.generationSchema
        )
        let request = LanguageModelExecutorGenerationRequest.make(
            transcript: Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Weather?"))]))]),
            enabledTools: [definition]
        )
        let body = try GeminiRequestBuilder.build(
            from: request,
            model: .gemini3_1_pro,
            fixedThinkingBudget: nil
        )
        #expect(body["tools"]?[0]["functionDeclarations"]?[0]["name"] == .string("weather"))
    }

    @Test func functionCallReplayKeepsGeminiIDAndSignatureAtPartLevel() throws {
        let transcript = Transcript(entries: [
            .prompt(.init(segments: [.text(.init(content: "Fetch the file"))])),
            .toolCalls(.init([
                .init(
                    id: "call_3234106",
                    toolName: "filepath_fetcher_tool",
                    arguments: try GeneratedContent(json: "{}")
                )
            ])),
            .toolOutput(.init(
                id: "call_3234106",
                toolName: "filepath_fetcher_tool",
                segments: [.text(.init(content: "Sources/App.swift"))]
            )),
        ])
        let body = try GeminiRequestBuilder.build(
            from: .make(transcript: transcript),
            model: .gemini3_1_pro,
            fixedThinkingBudget: nil
        )
        #expect(body["contents"]?[1]["parts"]?[0]["functionCall"]?["id"] == .string("call_3234106"))
        #expect(body["contents"]?[2]["parts"]?[0]["functionResponse"]?["id"] == .string("call_3234106"))
    }

    @Test func emptyFunctionArgumentsAreRepresentedAsAnEmptyJSONObject() throws {
        let arguments = try GeneratedContent(json: "{}")
        #expect(GeminiJSONValue(arguments).jsonText == "{}")
    }

    @Test func adjacentGeminiSSEPayloadsAreIndividualJSONDocuments() throws {
        let first = #"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"filepath_fetcher_tool","args":{},"id":"call_1"}}]}}]}"#
        let second = #"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"code_fetcher_tool","args":{},"id":"call_2"}}]}}]}"#
        let third = #"{"candidates":[{"content":{"parts":[{"text":""}]},"finishReason":"STOP"}]}"#

        for payload in [first, second, third] {
            let value = try JSONDecoder().decode(GeminiJSONValue.self, from: Data(payload.utf8))
            #expect(value["candidates"]?[0] != nil)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GeminiJSONValue.self, from: Data((first + second).utf8))
        }
    }
}

@Generable
private struct TestArguments {
    var city: String
}
