//
//  Extensions.swift
//  MonadicJSON
//
//  Created by Charlotte Tortorella on 23/4/19.
//

import Foundation
import SwiftCheck
import CoreGraphics
@testable import MonadicJSON

protocol TopLevelDecoder: CustomStringConvertible {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
    func setDateDecodingStrategy(_ strategy: JSONDecoder.DateDecodingStrategy)
    func setDataDecodingStrategy(_ strategy: JSONDecoder.DataDecodingStrategy)
}

extension MonadicJSONDecoder: TopLevelDecoder {
    func setDateDecodingStrategy(_ strategy: JSONDecoder.DateDecodingStrategy) {
        dateDecodingStrategy = yield {
            switch strategy {
            case .deferredToDate:
                return .deferredToDate
            case .iso8601:
                return .iso8601
            case .secondsSince1970:
                return .secondsSince1970
            case .millisecondsSince1970:
                return .millisecondsSince1970
            case let .custom(closure):
                return .custom(closure)
            case let .formatted(formatter):
                return .formatted(formatter)
            @unknown default:
                fatalError()
            }
        }
    }
    
    func setDataDecodingStrategy(_ strategy: JSONDecoder.DataDecodingStrategy) {
        dataDecodingStrategy = yield {
            switch strategy {
            case .base64:
                return .base64
            case .deferredToData:
                return .deferredToData
            case let .custom(closure):
                return .custom(closure)
            @unknown default:
                fatalError()
            }
        }
    }
    
    public var description: String {
        return "Monadic"
    }
}

extension JSONDecoder: TopLevelDecoder {
    func setDateDecodingStrategy(_ strategy: JSONDecoder.DateDecodingStrategy) {
        dateDecodingStrategy = strategy
    }
    
    func setDataDecodingStrategy(_ strategy: JSONDecoder.DataDecodingStrategy) {
        dataDecodingStrategy = strategy
    }
    
    public var description: String {
        return "Foundation"
    }
}

extension Result {
    var succeeded: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
    
    var failed: Bool {
        return !succeeded
    }
    
    var success: Success? {
        switch self {
        case let .success(value):
            return value
        case .failure:
            return nil
        }
    }
    
    var failure: Failure? {
        switch self {
        case .success:
            return nil
        case let .failure(error):
            return error
        }
    }
}

extension Data: Arbitrary {
    public static var arbitrary: Gen<Data> {
        return [UInt8].arbitrary.map { Data($0) }
    }
}

extension Date: Arbitrary {
    public static var arbitrary: Gen<Date> {
        return Int.arbitrary.map(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
    }
}

extension Decimal: Arbitrary {
    public static var arbitrary: Gen<Decimal> {
        return Double.arbitrary.map { Decimal($0) }
    }
}

extension CGFloat: Arbitrary {
    public static var arbitrary: Gen<CGFloat> {
        return Double.arbitrary.map { CGFloat($0) }
    }
}

extension Gen {
    public func map<U>(_ keyPath: KeyPath<A, U>) -> Gen<U> {
        return map { $0[keyPath: keyPath] }
    }
    
    public func filterMap<U>(_ transform: @escaping (A) -> U?) -> Gen<U> {
        return map(transform).suchThat { $0 != nil }.map { $0! }
    }
}

extension Gen where A: Sequence, A.Element == UnicodeScalar {
    var string: Gen<String> {
        return map { String($0.map(Character.init)) }
    }
}

extension Gen where A == String {
    var randomlyCapitalized: Gen {
        return self
            .map { $0.map(String.init).map(Gen.pure).map { $0.ap(.fromElements(of: [{ $0.capitalized }, { $0 }])) } }
            .flatMap(sequence)
            .map { $0.joined() }
    }
}

extension UnicodeScalar {
    static func allScalars(from first: UnicodeScalar, upTo last: Unicode.Scalar) -> [UnicodeScalar] {
        return Array(first.value ..< last.value).compactMap(UnicodeScalar.init)
    }
    
    static func allScalars(from first: UnicodeScalar, through last: UnicodeScalar) -> [UnicodeScalar] {
        return allScalars(from: first, upTo: last) + [last]
    }
}

extension Collection {
    func intersperse(element: Element) -> [Element] {
        return Array(zip(self, repeatElement(element, count: numericCast(count))).flatMap { [$0, $1] }.dropLast())
    }
    
    func intersperse(_ gen: Gen<Element>) -> [Element] {
        return Array(
            zip(self, repeatElement((), count: numericCast(count)).map { _ in gen.generate })
                .flatMap { [$0, $1] }
                .dropLast()
        )
    }
    
    func envelop(_ gen: Gen<Element>) -> [Element] {
        return Array([[gen.generate], intersperse(gen), [gen.generate]].joined())
    }
}

extension Collection where Element == String {
    func envelop(_ set: Set<UnicodeScalar>) -> [String] {
        let gen = Gen.fromElements(of: set).map(Character.init)
        return envelop(UInt.arbitrary.map { String(repeating: gen.generate, count: numericCast($0)) })
    }
}

extension JSONParser {
    static func parseStream(_ string: String) -> Result<JSON, JSONParser.Error> {
        let d = string.data(using: .utf8)!
        let i = InputStream(data: d)
        i.open()
        defer {
            i.close()
        }
        return JSONParser.parse(stream: i)
    }

    static func parse(_ string: String) -> Result<JSON, JSONParser.Error> {
        return JSONParser.parse(data: string.data(using: .utf8)!)
    }
    
    static func parseString(_ string: String) -> Result<String, JSONParser.Error.String> {
        var index = 0
        return JSONParser.parseString(scalars: Array(string.unicodeScalars), index: &index)
    }

    static func parseStringStream(_ string: String) -> Result<String, JSONParser.Error.String> {
        let d = string.data(using: .utf8)!
        let i = InputStream(data: d)
        i.open()
        defer {
            i.close()
        }
        var index = 0
        var scalar = i.getNextScalar()
        return JSONParser.parseStringStream(stream: i, scalar: &scalar, index: &index)
    }
}

extension String {
    private var escapes: [(String, String)] {
        return [("\\", "\\\\"), ("\"", "\\\"")]
    }
    
    var encoded: String {
        return ["\"", escapes.reduce(self) { $0.replacingOccurrences(of: $1.0, with: $1.1) }, "\""].joined()
    }
    
    var reified: String {
        return escapes.reduce(String(dropFirst().dropLast())) { $0.replacingOccurrences(of: $1.1, with: $1.0) }
    }
}

extension JSON: Arbitrary {
    public static var arbitraryNonRecursive: Gen<JSON> {
        return .one(of: [
            .pure(.null),
            randomNumbers.map(JSON.number),
            String.arbitrary.map(JSON.string),
            Bool.arbitrary.map(JSON.bool)
            ]
        )
    }
    
    public static var arbitrary: Gen<JSON> {
        return .one(of: [
            .pure(.null),
            randomNumbers.map(JSON.number),
            String.arbitrary.map(JSON.string),
            Bool.arbitrary.map(JSON.bool),
            arbitraryNonRecursive.proliferate.map(JSON.array),
            Gen.zip(String.arbitrary, arbitraryNonRecursive).proliferate.map { Dictionary($0, uniquingKeysWith: { $1 }) }.map(JSON.dictionary)
            ]
        )
    }
}

extension Int: Integer {}
extension Int8: Integer {}
extension Int16: Integer {}
extension Int32: Integer {}
extension Int64: Integer {}
extension UInt: Integer {}
extension UInt8: Integer {}
extension UInt16: Integer {}
extension UInt32: Integer {}
extension UInt64: Integer {}
