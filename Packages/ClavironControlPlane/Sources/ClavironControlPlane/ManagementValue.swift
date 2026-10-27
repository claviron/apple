import Foundation

/// JSON values keep integers and decimal numbers out of Double's precision range.
public enum ManagementValue: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case string(String)
    case integer(Int64)
    case unsigned(UInt64)
    case number(Decimal)
    case array([ManagementValue])
    case object([String: ManagementValue])

    public init(from decoder: any Decoder) throws {
        guard decoder.codingPath.count <= 32 else {
            throw ManagementClientError("The management document exceeds the supported nesting depth.")
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Int64.self) { self = .integer(value) }
        else if let value = try? container.decode(UInt64.self) { self = .unsigned(value) }
        else if let value = try? container.decode(Decimal.self) { self = .number(value) }
        else if let value = try? container.decode([ManagementValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: ManagementValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .unsigned(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    /// Receiver policy: at most 1 MiB per JSON field and 32 nested containers.
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576 else {
            throw ManagementClientError("The management document exceeds the supported size.")
        }
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch { throw ManagementClientError("The server returned an invalid or unsupported management document.") }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 1_048_576 else {
            throw ManagementClientError("The management document exceeds the supported size.")
        }
        return data
    }

    public var object: [String: Self]? { if case let .object(value) = self { value } else { nil } }
    public var string: String? { if case let .string(value) = self { value } else { nil } }
    public var array: [Self]? { if case let .array(value) = self { value } else { nil } }
    public var bool: Bool? { if case let .bool(value) = self { value } else { nil } }
    public var text: String {
        if case let .string(value) = self { return value }
        return (try? String(decoding: encoded(), as: UTF8.self)) ?? ""
    }
}

public struct ManagementClientError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
