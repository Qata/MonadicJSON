//
//  JSON.swift
//  MonadicJSON macOS
//
//  Created by Charlotte Tortorella on 18/4/19.
//

import Foundation

fileprivate struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    public init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

fileprivate struct Null {
}

extension Null: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if !container.decodeNil() {
            throw DecodingError.valueNotFound(Null.self, .init(codingPath: [], debugDescription: "", underlyingError: nil))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

public indirect enum JSON: Hashable, Codable {
    case null
    case string(String)
    case number(String)
    case bool(Bool)
    case object([String: JSON])
    case array([JSON])
    
    public func encodable() throws -> some Encodable {
        func recurse(json: JSON) throws -> AnyEncodable {
            switch json {
            case let .object(value):
                return try .init(value.mapValues(recurse))
            case let .array(value):
                return try .init(value.map(recurse))
            case let .number(value):
                return try .init(Decimal(value, format: .number))
            case let .string(value):
                return .init(value)
            case let .bool(value):
                return .init(value)
            case .null:
                return .init(Null())
            }
        }
        return try recurse(json: self)
    }
}
