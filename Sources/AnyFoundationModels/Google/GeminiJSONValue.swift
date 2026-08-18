import Foundation
import FoundationModels

@available(anyAppleOS 27.0, *)
enum GeminiJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double?)
    case string(String)
    case array([GeminiJSONValue])
    case object([String: GeminiJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([GeminiJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: GeminiJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(_ key: String) -> GeminiJSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    subscript(_ index: Int) -> GeminiJSONValue? {
        if case .array(let values) = self, values.indices.contains(index) { return values[index] }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var jsonText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(self), as: UTF8.self)
    }
}

@available(anyAppleOS 27.0, *)
extension GeminiJSONValue {
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
}
