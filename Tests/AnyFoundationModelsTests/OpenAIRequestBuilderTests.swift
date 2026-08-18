import FoundationModels
import Testing

@testable import AnyFoundationModels

@available(anyAppleOS 27, *)
@Suite struct OpenAIRequestBuilderTests {
    @Test func buildsInstructionsAndPrompt() throws {
        let transcript = Transcript(entries: [
            .instructions(.init(segments: [.text(.init(content: "Be concise."))], toolDefinitions: [])),
            .prompt(.init(segments: [.text(.init(content: "Hello"))])),
        ])
        let request = try OpenAIRequestBuilder.build(
            from: .make(transcript: transcript),
            model: .gpt5_6_sol
        )
        #expect(request.instructions == "Be concise.")
        #expect(request.input.count == 1)
        #expect(request.input[0]["role"] == .string("user"))
    }

    @Test func mapsStructuredOutputToStrictJSONSchema() throws {
        @Generable struct Output { var city: String }
        let request = LanguageModelExecutorGenerationRequest.make(
            transcript: Transcript(entries: [.prompt(.init(segments: [.text(.init(content: "Plan"))]))]),
            schema: Output.generationSchema
        )
        let built = try OpenAIRequestBuilder.build(from: request, model: .gpt5_6_sol)
        #expect(built.text?["format"]?["type"] == .string("json_schema"))
        #expect(built.text?["format"]?["strict"] == .bool(true))
    }
}

@Suite struct OpenAISSETests {
    @Test func errorPayloadDecodesAfterAdjacentFrames() throws {
        let first = #"{"type":"response.created","sequence_number":0}"#
        let second = #"{"type":"response.in_progress","sequence_number":1}"#
        let error = #"{"type":"error","error":{"type":"insufficient_quota","code":"credit_balance_exhausted","message":"No credits"},"sequence_number":2}"#

        let combined = "\(first)\(second)"
        #expect(try JSONDecoder().decode(OpenAIStreamEvent.self, from: Data(first.utf8)).type == "response.created")
        #expect(try JSONDecoder().decode(OpenAIStreamEvent.self, from: Data(second.utf8)).type == "response.in_progress")
        #expect(try JSONDecoder().decode(OpenAIStreamEvent.self, from: Data(error.utf8)).type == "error")
        #expect(!combined.isEmpty)
    }
}
