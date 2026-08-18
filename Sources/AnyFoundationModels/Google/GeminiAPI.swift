import Foundation

struct GeminiAPIError: Error, LocalizedError, Sendable {
    let status: Int
    let message: String
    let requestID: String?

    var errorDescription: String? {
        requestID.map { "HTTP \(status): \(message) (request_id: \($0))" } ?? "HTTP \(status): \(message)"
    }
}

@available(anyAppleOS 27.0, *)
struct GeminiClient: Sendable {
    let baseURL: URL
    let auth: GeminiAuthMode
    let timeout: TimeInterval

    func stream(model: String, body: GeminiJSONValue) -> AsyncThrowingStream<GeminiJSONValue, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(
                        url: baseURL.appending(path: "models/\(model):streamGenerateContent")
                            .appending(queryItems: [URLQueryItem(name: "alt", value: "sse")])
                    )
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    switch auth {
                    case .apiKey(let key):
                        guard !key.isEmpty else { throw GeminiError.missingCredential }
                        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
                    case .proxied(let headers):
                        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
                    }
                    request.httpBody = try JSONEncoder().encode(body)
                    let configuration = URLSessionConfiguration.default
                    configuration.timeoutIntervalForRequest = timeout
                    let (bytes, response) = try await URLSession(configuration: configuration).bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
                        throw GeminiAPIError(
                            status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                            message: "Gemini request failed",
                            requestID: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-request-id")
                        )
                    }

                    // SSE frames are separated by a blank line. AsyncBytes
                    // lines do not expose that separator reliably, so parse
                    // the byte stream and flush one JSON payload per frame.
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
                        // event:, id:, retry:, and comments are ignored;
                        // Gemini's JSON payload has the event content.
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
        into continuation: AsyncThrowingStream<GeminiJSONValue, Error>.Continuation
    ) throws {
        guard !data.isEmpty, data != "[DONE]" else { return }
        let value = try JSONDecoder().decode(GeminiJSONValue.self, from: Data(data.utf8))
        if let error = value["error"] {
            throw GeminiAPIError(
                status: Int(error["code"]?.numberValue ?? 0),
                message: error["message"]?.stringValue ?? "Gemini stream failed",
                requestID: nil
            )
        }
        continuation.yield(value)
    }
}

@available(anyAppleOS 27.0, *)
private extension GeminiJSONValue {
    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}
