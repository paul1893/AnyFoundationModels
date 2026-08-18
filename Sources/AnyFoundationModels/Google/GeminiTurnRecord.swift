import Foundation
import FoundationModels

/// Opaque Gemini data needed to replay a function call on a later turn.
@available(anyAppleOS 27.0, *)
enum GeminiTurnRecord {
    static let metadataKey = "gemini.content"

    static func metadata(
        id: String,
        thoughtSignature: String
    ) -> [String: any ConvertibleToGeneratedContent] {
        let value = GeminiJSONValue.object([
            "id": .string(id),
            "thoughtSignature": .string(thoughtSignature),
        ]).jsonText
        return [metadataKey: value]
    }
}
