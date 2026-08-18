import Foundation

public enum GeminiError: LocalizedError, Sendable {
    case missingCredential
    case blocked(String)
    case api(status: Int, message: String, requestID: String?)

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            "No Gemini credential. Provide an API key or configure a proxy."
        case .blocked(let message):
            "Gemini blocked the request: \(message)"
        case .api(let status, let message, let requestID):
            requestID.map { "HTTP \(status): \(message) (request_id: \($0))" } ?? "HTTP \(status): \(message)"
        }
    }
}
