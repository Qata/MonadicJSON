import Foundation
import SwiftCheck
import CoreGraphics
@testable import MonadicJSON

// MARK: - TopLevelDecoder Protocol

/// A protocol that abstracts a top-level decoder.
/// Conforming types must provide a method to decode any Decodable type from data,
/// and allow customization of date and data decoding strategies.
protocol TopLevelDecoder: CustomStringConvertible {
    /// Decodes an instance of type T from the given data.
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
    
    /// Sets the strategy used for decoding dates.
    func setDateDecodingStrategy(_ strategy: JSONDecoder.DateDecodingStrategy)
    
    /// Sets the strategy used for decoding binary data.
    func setDataDecodingStrategy(_ strategy: JSONDecoder.DataDecodingStrategy)
}

// MARK: - MonadicJSONDecoder Conformance

/// Extend MonadicJSONDecoder (our custom decoder) to conform to CustomStringConvertible.
/// This helps identify it during testing.
extension MonadicJSONDecoder: @retroactive CustomStringConvertible {}

/// Conform MonadicJSONDecoder to TopLevelDecoder.
/// This implementation demonstrates how to map JSONDecoder strategies using a helper (`yield`).
extension MonadicJSONDecoder: TopLevelDecoder {
    /// Sets the date decoding strategy using a monadic-like helper.
    /// The `yield` function is used here to defer evaluation.
    func setDateDecodingStrategy(_ strategy: JSONDecoder.DateDecodingStrategy) {
        dateDecodingStrategy = switch strategy {
        case .deferredToDate:
            .deferredToDate
        case .iso8601:
            .iso8601
        case .secondsSince1970:
            .secondsSince1970
        case .millisecondsSince1970:
            .millisecondsSince1970
        case let .custom(closure):
            .custom(closure)
        case let .formatted(formatter):
            .formatted(formatter)
        @unknown default:
            fatalError("Unknown date decoding strategy")
        }
    }
    
    /// Sets the data decoding strategy using the same deferred evaluation approach.
    func setDataDecodingStrategy(_ strategy: JSONDecoder.DataDecodingStrategy) {
        dataDecodingStrategy = switch strategy {
        case .base64:
            .base64
        case .deferredToData:
            .deferredToData
        case let .custom(closure):
            .custom(closure)
        @unknown default:
            fatalError("Unknown data decoding strategy")
        }
    }
    
    /// Provides a description to help differentiate this decoder from others.
    public var description: String {
        "Monadic" // Note: Despite the name, this decoder isn’t truly monadic.
    }
}

// MARK: - JSONDecoder Conformance

/// Extend the built-in JSONDecoder to conform to CustomStringConvertible.
extension JSONDecoder: @retroactive CustomStringConvertible {}

/// Conform JSONDecoder to TopLevelDecoder.
/// This implementation directly sets the strategies without extra transformation.
extension JSONDecoder: TopLevelDecoder {
    func setDateDecodingStrategy(_ strategy: JSONDecoder.DateDecodingStrategy) {
        dateDecodingStrategy = strategy
    }
    
    func setDataDecodingStrategy(_ strategy: JSONDecoder.DataDecodingStrategy) {
        dataDecodingStrategy = strategy
    }
    
    public var description: String {
        "Foundation"
    }
}

// MARK: - Result Extensions

/// Extensions to Result to provide convenient properties for testing.
extension Result {
    /// Returns true if the result is a success.
    var succeeded: Bool {
        switch self {
        case .success:
            true
        case .failure:
            false
        }
    }
    
    /// Returns true if the result is a failure.
    var failed: Bool {
        !succeeded
    }
    
    /// Extracts the success value, if any.
    var success: Success? {
        switch self {
        case let .success(value):
            value
        case .failure:
            nil
        }
    }
    
    /// Extracts the error, if any.
    var failure: Failure? {
        switch self {
        case .success:
            nil
        case let .failure(error):
            error
        }
    }
}

// MARK: - Arbitrary Conformances

/// Conform Data to Arbitrary so that random Data values can be generated for testing.
extension Data: @retroactive Arbitrary {
    public static var arbitrary: Gen<Data> {
        // Generate an array of UInt8 values and convert it to Data.
        [UInt8].arbitrary.map { Data($0) }
    }
}

/// Conform Date to Arbitrary for generating random dates.
/// Dates are created from a random integer interpreted as a TimeInterval.
extension Date: @retroactive Arbitrary {
    public static var arbitrary: Gen<Date> {
        Int.arbitrary
            .map(TimeInterval.init)
            .map { Date(timeIntervalSince1970: $0) }
    }
}

/// Conform Decimal to Arbitrary by generating a random Double and converting it.
extension Decimal: @retroactive Arbitrary {
    public static var arbitrary: Gen<Decimal> {
        Double.arbitrary.map { Decimal($0) }
    }
}

/// Conform CGFloat to Arbitrary by generating a random Double and converting it.
extension CGFloat: @retroactive Arbitrary {
    public static var arbitrary: Gen<CGFloat> {
        Double.arbitrary.map { CGFloat($0) }
    }
}

// MARK: - Gen Extensions

/// Extend Gen with helper methods to simplify common operations.
extension Gen {
    /// Maps and filters a generated value.
    /// The transform can return an optional, and only non-nil results are kept.
    public func filterMap<U>(_ transform: @escaping (A) -> U?) -> Gen<U> {
        map(transform).suchThat { $0 != nil }.map { $0! }
    }
}

/// When the generated value is a sequence of UnicodeScalars, this extension provides a method to produce a String.
extension Gen where A: Sequence, A.Element == UnicodeScalar {
    var string: Gen<String> {
        map { scalars in
            String(scalars.map { Character($0) })
        }
    }
}

/// When the generated value is a String, this extension allows creation of a randomly capitalized version.
/// It demonstrates how to manipulate and recombine generated values.
extension Gen where A == String {
    var randomlyCapitalized: Gen<String> {
        self.map { original in
            // For each character, choose randomly between its capitalized or original form.
            original.map { character in
                Gen.pure(String(character))
                    .ap(.fromElements(of: [{ $0.capitalized }, { $0 }]))
            }
        }
        .flatMap(sequence)
        .map { $0.joined() }
    }
}

// MARK: - UnicodeScalar Extensions

/// Helper methods for working with Unicode scalars.
extension UnicodeScalar {
    /// Returns all UnicodeScalars starting from `first` up to (but not including) `last`.
    static func allScalars(from first: UnicodeScalar, upTo last: Unicode.Scalar) -> [UnicodeScalar] {
        Array(first.value..<last.value).compactMap(UnicodeScalar.init)
    }
    
    /// Returns all UnicodeScalars starting from `first` through `last` (inclusive).
    static func allScalars(from first: UnicodeScalar, through last: UnicodeScalar) -> [UnicodeScalar] {
        allScalars(from: first, upTo: last) + [last]
    }
}

// MARK: - Collection Extensions

/// Adds helper methods to Collection for interspersing elements and enveloping sequences.
extension Collection {
    /// Inserts the given element between each element of the collection.
    func intersperse(element: Element) -> [Element] {
        Array(
            zip(
                self,
                repeatElement(element, count: numericCast(count))
            )
            .flatMap {
                [$0, $1]
            }
            .dropLast()
        )
    }
    
    /// Uses a generator to produce elements to intersperse between each element of the collection.
    func intersperse(_ gen: Gen<Element>) -> [Element] {
        Array(
            zip(
                self,
                repeatElement((), count: numericCast(count)).map {
                    _ in gen.generate
                }
            )
            .flatMap {
                [$0, $1]
            }
            .dropLast()
        )
    }
    
    /// Envelops the collection by adding a generated element at the beginning and end.
    func envelop(_ gen: Gen<Element>) -> [Element] {
        Array(
            [
                [gen.generate],
                intersperse(gen),
                [gen.generate]
            ].joined()
        )
    }
}

/// When the Collection’s elements are Strings, this extension creates an envelope from a set of Unicode scalars.
/// This is useful for adding consistent formatting or decoration.
extension Collection where Element == String {
    func envelop(_ set: Set<UnicodeScalar>) -> [String] {
        // Generate a Character from one of the provided Unicode scalars.
        let gen = Gen.fromElements(of: set).map { Character($0) }
        // Use an arbitrary UInt value to decide how many times to repeat the generated character.
        return envelop(
            UInt.arbitrary.map {
                String(
                    repeating: gen.generate,
                    count: numericCast($0)
                )
            }
        )
    }
}

// MARK: - JSONParser Extensions

/// Extensions on JSONParser to simplify parsing from strings and streams.
extension JSONParser {
    /// Parses JSON from a string by converting it to an InputStream.
    static func parseStream(_ string: String) -> Result<JSON, JSONParser.Error> {
        let d = string.data(using: .utf8)! // Assumes valid UTF-8.
        let i = InputStream(data: d)
        i.open()
        defer {
            i.close()
        }
        return JSONParser.parse(stream: i)
    }

    /// Parses JSON directly from a string by converting it to Data.
    static func parse(_ string: String) -> Result<JSON, JSONParser.Error> {
        return JSONParser.parse(data: string.data(using: .utf8)!)
    }
    
    /// Parses a JSON string literal (removing the surrounding quotes) into a Swift String.
    static func parseString(_ string: String) -> Result<String, JSONParser.Error.String> {
        var index = 0
        return JSONParser.parseString(scalars: Array(string.unicodeScalars), index: &index)
    }

    /// Parses a JSON string literal from an InputStream.
    static func parseStringStream(_ string: String) -> Result<String, JSONParser.Error.String> {
        let d = string.data(using: .utf8)! // Assumes valid UTF-8.
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

// MARK: - String Extensions

/// Adds convenience methods to String for JSON escaping and unescaping.
extension String {
    /// Defines pairs of literal and escaped substrings for JSON.
    private var escapes: [(literal: String, escaped: String)] {
        return [
            ("\\", "\\\\"), // Escape backslashes.
            ("\"", "\\\"")  // Escape double quotes.
        ]
    }
    
    /// Returns the JSON-encoded version of the string (i.e. surrounded by quotes with proper escaping).
    var encoded: String {
        return [
            "\"",
            // Replace each literal occurrence with its escaped version.
            escapes.reduce(self) { $0.replacingOccurrences(of: $1.literal, with: $1.escaped) },
            "\""
        ].joined()
    }
    
    /// Returns the unescaped, original version of a JSON string.
    /// This is done by removing the surrounding quotes and reversing the escape replacements.
    var reified: String {
        let core = String(dropFirst().dropLast())
        return escapes.reduce(core) { $0.replacingOccurrences(of: $1.escaped, with: $1.literal) }
    }
}

// MARK: - JSON Arbitrary Conformance

/// Extend JSON (our model for JSON values) to conform to Arbitrary so that random JSON values can be generated.
extension JSON: @retroactive Arbitrary {
    /// Generates non-recursive JSON values (primitive types).
    public static var arbitraryNonRecursive: Gen<JSON> {
        return .one(of: [
            .pure(.null),
            randomNumbers.map(JSON.number),
            String.arbitrary.map(JSON.string),
            Bool.arbitrary.map(JSON.bool)
        ])
    }
    
    /// Generates recursive JSON values including arrays and objects.
    public static var arbitrary: Gen<JSON> {
        return .one(of: [
            .pure(.null),
            randomNumbers.map(JSON.number),
            String.arbitrary.map(JSON.string),
            Bool.arbitrary.map(JSON.bool),
            // Generate an array of non-recursive JSON values.
            arbitraryNonRecursive.proliferate.map(JSON.array),
            // Generate a dictionary (object) from random key-value pairs.
            Gen.zip(String.arbitrary, arbitraryNonRecursive)
                .proliferate
                .map { Dictionary($0, uniquingKeysWith: { $1 }) }
                .map(JSON.object)
        ])
    }
}

// MARK: - Integer Protocol Conformance

/// Extend standard integer types to conform to the Integer protocol.
/// This allows our generators and tests to work generically with any integer type.
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
