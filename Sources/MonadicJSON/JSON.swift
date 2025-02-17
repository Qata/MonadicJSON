import Foundation

// MARK: - Type-Erased Encodable Wrapper

/// A type-erased wrapper for any Encodable value.
/// This allows us to store or return an Encodable value without knowing its concrete type.
fileprivate struct AnyEncodable: Encodable {
    /// A closure that encodes the wrapped value.
    private let _encode: (Encoder) throws -> Void

    /// Initialize with any Encodable type.
    /// The wrapped type’s encode(to:) method is stored in the _encode closure.
    public init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }

    /// When encoding, simply call the stored _encode closure.
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - Null Representation

/// A simple type to represent a JSON null value.
/// This type exists solely to distinguish JSON null values during encoding/decoding.
fileprivate struct Null {
}

// Extend Null to support Codable so that it can be used when encoding/decoding JSON nulls.
extension Null: Codable {
    /// Decodes a Null value by ensuring the container contains a nil.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // If the container does not contain nil, then throw an error.
        if !container.decodeNil() {
            throw DecodingError.valueNotFound(
                Null.self,
                .init(codingPath: [],
                      debugDescription: "",
                      underlyingError: nil)
            )
        }
    }

    /// Encodes the Null value as a nil value.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

// MARK: - JSON Decimal Error

/// A simple error type that is thrown when a JSON number cannot be converted into a Decimal.
public struct JSONDecimalError: Error {
}

// MARK: - JSON Value Representation

/// An enumeration representing a JSON value.
/// This enum supports null, strings, numbers, booleans, objects (dictionaries), and arrays.
/// The enum is declared as 'indirect' to allow recursive definitions.
public indirect enum JSON: Hashable, Codable {
    case null
    case string(String)
    /// A JSON number is represented as a String.
    /// This allows precise control over formatting and avoids floating-point inaccuracies.
    case number(String)
    case bool(Bool)
    /// Represents a JSON object (dictionary) where keys are Strings and values are JSON.
    case object([String: JSON])
    /// Represents a JSON array of JSON values.
    case array([JSON])
    
    /// Returns an Encodable representation of this JSON value.
    /// This method recursively converts the JSON enum into a tree of type-erased AnyEncodable values,
    /// which can then be encoded using a standard JSONEncoder.
    public func encodable() throws -> Encodable {
        /// A recursive helper function that transforms a JSON value into an AnyEncodable.
        func recurse(json: JSON) throws -> AnyEncodable {
            switch json {
            case let .object(value):
                // For a JSON object, map each value recursively to an AnyEncodable.
                // The keys remain unchanged.
                return try .init(value.mapValues(recurse))
            case let .array(value):
                // For a JSON array, map each element recursively.
                return try .init(value.map(recurse))
            case let .number(value):
                // For a JSON number, attempt to convert the string to a Decimal.
                // If conversion fails, throw a JSONDecimalError.
                guard let decimal = Decimal(string: value) else {
                    throw JSONDecimalError()
                }
                return .init(decimal)
            case let .string(value):
                // Wrap a string directly.
                return .init(value)
            case let .bool(value):
                // Wrap a boolean value.
                return .init(value)
            case .null:
                // For JSON null, wrap our Null struct.
                return .init(Null())
            }
        }
        // Begin the recursion from self.
        return try recurse(json: self)
    }
}
