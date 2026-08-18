import Foundation

public enum OpenAIError: LocalizedError, Sendable {
    case missingCredential
    case insufficientQuota(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential: "No OpenAI credential. Provide an API key or configure a proxy."
        case .insufficientQuota(let message): message
        }
    }
}
