import Foundation

struct OpenAIAPIError: Error, Codable, LocalizedError, Sendable {
    let message: String
    let type: String?
    let code: String?
    let param: String?
    let requestID: String?

    var errorDescription: String? {
        requestID.map { "\(message) (request_id: \($0))" } ?? message
    }
}

struct OpenAIResponseRequest: Encodable, Sendable {
    var model: String
    var input: [OpenAIJSONValue]
    var instructions: String?
    var stream = true
    var maxOutputTokens: Int?
    var temperature: Double?
    var reasoning: OpenAIJSONValue?
    var tools: [OpenAIJSONValue]?
    var toolChoice: OpenAIJSONValue?
    var text: OpenAIJSONValue?

    enum CodingKeys: String, CodingKey {
        case model, input, instructions, stream
        case maxOutputTokens = "max_output_tokens"
        case temperature, reasoning, tools
        case toolChoice = "tool_choice"
        case text
    }
}

struct OpenAIStreamEvent: Decodable, Sendable {
    let type: String
    let sequenceNumber: Int?
    let item: OpenAIJSONValue?
    let delta: String?
    let itemID: String?
    let outputIndex: Int?
    let contentIndex: Int?
    let response: OpenAIJSONValue?
    let usage: OpenAIJSONValue?
    let error: OpenAIJSONValue?

    enum CodingKeys: String, CodingKey {
        case type, item, delta, response, usage, error
        case sequenceNumber = "sequence_number"
        case itemID = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
    }
}

struct OpenAIHTTPClient: Sendable {
    let baseURL: URL
    let auth: AuthMode
    let timeout: TimeInterval

    func stream(_ body: OpenAIResponseRequest) -> AsyncThrowingStream<OpenAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appending(path: "responses"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    switch auth {
                    case .apiKey(let key):
                        guard !key.isEmpty else { throw OpenAIError.missingCredential }
                        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    case .proxied(let headers):
                        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
                    }
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .sortedKeys
                    request.httpBody = try encoder.encode(body)
                    let configuration = URLSessionConfiguration.default
                    configuration.timeoutIntervalForRequest = timeout
                    let (bytes, response) = try await URLSession(configuration: configuration).bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        let payload = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: body)
                        let apiError = payload?.error
                        throw OpenAIAPIError(
                            message: apiError?.message ?? String(decoding: body.prefix(2048), as: UTF8.self),
                            type: apiError?.type,
                            code: apiError?.code,
                            param: apiError?.param,
                            requestID: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-request-id")
                        )
                    }
                    // SSE frames are separated by a blank line. Do not use
                    // AsyncBytes.lines here: it does not expose the blank
                    // separator, which can concatenate adjacent JSON frames.
                    var data = ""
                    var line: [UInt8] = []
                    var previousByteWasCR = false

                    func flush() throws {
                        guard !data.isEmpty else { return }
                        try emit(data, into: continuation)
                        data = ""
                    }

                    func handle(_ line: String) throws {
                        if line.isEmpty {
                            try flush()
                        } else if line.hasPrefix("data:") {
                            let payload = line.dropFirst(5)
                                .trimmingCharacters(in: .whitespaces)
                            data += data.isEmpty ? payload : "\n" + payload
                        }
                        // event:, id:, retry:, and comment lines are not
                        // needed: the JSON type identifies each event.
                    }

                    for try await byte in bytes {
                        switch byte {
                        case 10 where previousByteWasCR:
                            previousByteWasCR = false
                        case 10, 13:
                            previousByteWasCR = byte == 13
                            try handle(String(decoding: line, as: UTF8.self))
                            line.removeAll(keepingCapacity: true)
                        default:
                            previousByteWasCR = false
                            line.append(byte)
                        }
                    }
                    if !line.isEmpty {
                        try handle(String(decoding: line, as: UTF8.self))
                    }
                    try flush()
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func emit(
        _ data: String,
        into continuation: AsyncThrowingStream<OpenAIStreamEvent, Error>.Continuation
    ) throws {
        guard data != "[DONE]", !data.isEmpty else { return }
        let event = try JSONDecoder().decode(OpenAIStreamEvent.self, from: Data(data.utf8))
        if event.type == "error" {
            throw OpenAIAPIError(
                message: event.error?["message"]?.stringValue ?? "OpenAI stream failed",
                type: event.error?["type"]?.stringValue,
                code: event.error?["code"]?.stringValue,
                param: event.error?["param"]?.stringValue,
                requestID: nil
            )
        }
        continuation.yield(event)
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: OpenAIErrorPayload
}

private struct OpenAIErrorPayload: Decodable {
    let message: String
    let type: String?
    let code: String?
    let param: String?
}
