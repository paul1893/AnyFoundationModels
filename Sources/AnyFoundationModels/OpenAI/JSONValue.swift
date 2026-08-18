import Foundation

enum OpenAIJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([OpenAIJSONValue])
    case object([String: OpenAIJSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([OpenAIJSONValue].self) { self = .array(value) }
        else { self = .object(try c.decode([String: OpenAIJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }
}

extension OpenAIJSONValue {
    var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    subscript(_ key: String) -> OpenAIJSONValue? {
        if case .object(let value) = self { value[key] } else { nil }
    }
}
