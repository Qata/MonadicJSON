import XCTest
import SwiftCheck
@testable import MonadicJSON

/// A test suite for the JSON parser using SwiftCheck for property‐based testing.
/// Each test demonstrates how to use generators, properties, and SwiftCheck’s combinators
/// to validate JSON parsing behavior.
class JSONParserTests: XCTestCase {

    // MARK: - Known Issues & Regression Tests

    /// Test for a known issue with decimal values.
    ///
    /// This test verifies that:
    /// - The system JSONDecoder fails for some broken decimals.
    /// - Our custom MonadicJSONDecoder succeeds for these cases.
    ///
    /// If this test fails, it indicates that Foundation’s JSON parsing might have fixed
    /// the problem this library originally set out to solve.
    func testKnownBrokenDecimals() {
        // Create a generator from a list of known broken decimal strings.
        // We filter out any strings that can't be converted to Decimal.
        let gen = Gen.fromElements(of: brokenDecimals.compactMap { Decimal(string: $0) })
        
        // Test decoding with the standard JSONDecoder expecting failure.
        // We use a transformation to invert the property (expectFailure) so that a failure is expected.
        testDecoding(
            decoder: JSONDecoder(),
            gen: Decimal.arbitrary,
            transform: \.expectFailure
        )
        
        // Test decoding with our custom decoder which is expected to succeed.
        testDecoding(
            decoder: MonadicJSONDecoder(),
            gen: gen
        )
    }

    // MARK: - General Parser Robustness

    /// Verifies that random strings do not crash the parser.
    ///
    /// This property test generates random strings and passes them to the parser.
    /// The goal is to ensure that even invalid JSON input does not cause a crash.
    func testParserGenerally() {
        property("Random strings can't crash the parser") <- forAll { (string: String) in
            // Parse the string and ignore the result. The property always returns true.
            _ = JSONParser.parse(string)
            return true
        }
    }
    
    // MARK: - String Parsing Tests

    /// Tests that valid JSON strings are parsed correctly.
    ///
    /// This property test ensures that strings which conform to JSON's string literal rules
    /// are recognized as valid by the parser.
    func testStrings() {
        // Valid JSON strings (with surrounding quotes) should be parsed successfully.
        property("Strings are all valid") <- forAll(strings) { string in
            JSONParser.parseString(string).succeeded
        }
        
        // Strings that do not start or end with a double quote should fail.
        property("Strings are invalid if they don't start/end with '\"'") <- forAll(invalidStrings) { string in
            JSONParser.parseString(string).failed
        }
        
        // Test that a JSON string containing a Unicode escape with 4 hex digits is valid.
        property("Unicode with 4 hex digits is valid") <- forAllNoShrink(validUnicode) { (args: (scalar: UInt32, string: String)) in
            // The parsed string should yield the correct Unicode scalar value.
            JSONParser.parseString(args.string).success!.unicodeScalars.first!.value == args.scalar
        }
        
        // Verify that a string containing multiple Unicode escapes is parsed correctly.
        property("Unicode can occur multiple times in a string") <- forAllNoShrink(
            validUnicode.map { String($1.dropFirst().dropLast()) }.proliferate
        ) {
            // Construct a JSON string from the joined components.
            return JSONParser
                .parseString(
                    [
                        "\"",
                        $0.joined(),
                        "\""
                    ].joined()
                )
                .succeeded
        }
        
        // Ensure that Unicode escapes with less than 4 hex digits are rejected.
        property("Unicode with less than 4 hex digits is invalid") <- forAllNoShrink(
            Gen.zip(
                validUnicode.map { $1 },
                .fromElements(in: (2...5))
            ).map {
                // Drop the last few characters to simulate an incomplete Unicode escape.
                [String($0.dropLast($1)), "\""].joined()
            }
        ) { string in
            // Check that the parser returns a malformedUnicode error.
            switch JSONParser.parseString(string).failure {
            case .malformedUnicode?:
                return true
            default:
                return false
            }
        }
        
        // Ensure that completely unrepresentable Unicode escapes are rejected.
        property("Unrepresentable unicode is invalid") <- forAllNoShrink(invalidUnicode) { string in
            switch JSONParser.parseString(string).failure {
            case .malformedUnicode?:
                return true
            default:
                return false
            }
        }
        
        // Test that an array of JSON strings is parsed sequentially, and the index advances properly.
        property("An array of strings can be repeatedly parsed with the same index until they reach the end") <- forAllNoShrink(strings.proliferate) { strings in
            var index = 0
            let joined = strings.joined()
            let scalars = Array(joined.unicodeScalars)
            // For each string, the parser should successfully parse it, and the index should match.
            return (0..<strings.count).allSatisfy {
                JSONParser.parseString(
                    scalars: scalars,
                    index: &index
                ).success == strings[$0].reified
            } <?> "All strings parsed"
            ^&&^
            (index == scalars.endIndex) <?> "index == endIndex"
        }
    }
    
    // MARK: - Dictionary (Object) Parsing Tests

    /// Tests that valid JSON dictionaries (objects) are parsed correctly.
    func testDictionaries() {
        // Valid JSON dictionaries should parse without errors.
        property("Dictionaries are all valid") <- forAllNoShrink(dictionaries) { string in
            JSONParser.parse(string).succeeded
        }
        
        // Dictionaries with invalid string keys/values should fail.
        property("Dictionaries containing invalid strings are invalid") <- forAllNoShrink(
            dictionary(invalidAlphabetical, invalidAlphabetical)
        ) { string in
            JSONParser.parse(string).failed
        }
        
        // Unterminated dictionaries should produce a malformed error.
        property(
            "Dictionaries that are unterminated will result in a malformed error"
        ) <- forAllNoShrink(
            Gen.pure("[{\"\":")
                .proliferateNonEmpty
        ) { strings in
            switch JSONParser.parse(strings.joined()).failure {
            case .object(.malformed)?:
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - Array Parsing Tests

    /// Tests that valid JSON arrays are parsed correctly.
    func testArrays() {
        property("Arrays are all valid") <- forAllNoShrink(arrays) { string in
            JSONParser.parse(string).succeeded
        }
        
        // Arrays that include invalid strings should be rejected.
        property("Arrays containing invalid strings are invalid") <- forAllNoShrink(array(invalidAlphabetical)) { string in
            JSONParser.parse(string).failed
        }
        
        // Test that arrays with arbitrary levels of nesting produce a malformed error.
        property("Arrays can handle arbitrary nesting levels") <- forAllNoShrink(
            Gen.pure("[")
                .proliferateNonEmpty
                .map { $0.joined() }
        ) { string in
            switch JSONParser.parse(string).failure {
            case .array(.malformed)?:
                return true
            default:
                return false
            }
        }
        
        // Arrays that are unterminated should produce a malformed error.
        property("Unterminated arrays will result in malformed errors") <- forAllNoShrink(
            Gen.one(of: [
                strings,
                randomNumbers,
                arrays,
                dictionaries
            ]).map { "[" + $0 }
        ) { string in
            switch JSONParser.parse(string).failure {
            case .array(.malformed)?:
                return true
            default:
                return false
            }
        }
    }
    
    // MARK: - Number Parsing Tests

    /// Tests that valid JSON numbers are correctly parsed.
    func testNumbers() {
        property("Numbers are all valid") <- forAll(randomNumbers) { (string: String) in
            // The parser should recognize a valid number string and wrap it as a .number.
            JSONParser.parse(string).success == .number(string)
        }

        // Numbers that begin with a zero should be considered invalid.
        property("Numbers that begin with 0 are invalid") <- forAll(invalidJsonNumbers) { (string: String) in
            JSONParser.parse(string).failure == .number(.numberBeginningWithZero(index: 0))
        }

        // NaN (not-a-number) should not be accepted as valid JSON,
        // regardless of capitalisation.
        property("NaN is invalid") <- forAll(
            Gen.pure("nan")
                .randomlyCapitalized
        ) { (string: String) in
            JSONParser.parse(string).failed
        }
    }
    
    // MARK: - Boolean Parsing Tests

    /// Tests that boolean values are parsed correctly.
    func testBools() {
        property("Bools are all valid") <- forAll { (bool: Bool) in
            // Parse the string representation of the boolean.
            JSONParser.parse(bool.description).success == .bool(bool)
        }
        
        // Boolean strings with incorrect capitalization (e.g. "True" or "FALSE") should fail.
        property("Capitalised bools are invalid") <- forAll(
            Bool.arbitrary
                .map(\.description)
                .randomlyCapitalized
        ) { string in
            // If the string is not exactly "true" or "false", it should fail.
            (![true, false].contains(where: { $0.description == string })) ==> {
                JSONParser.parse(string).failed
            }
        }
    }
    
    // MARK: - Null Parsing Tests

    /// Tests that the JSON `null` value is parsed correctly.
    func testNull() {
        property("Null is valid") <- forAllNoShrink(.pure(())) { _ in
            JSONParser.parse("null").succeeded
        }
        
        // Null with incorrect capitalization should be rejected.
        property("Capitalised nulls are invalid") <- forAll(
            Gen.pure("null")
                .randomlyCapitalized
        ) { string in
            (string != "null") ==> {
                JSONParser.parse(string).failed
            }
        }
    }
    
    // MARK: - Oversized Integer Tests

    /// Tests that attempting to decode an integer larger than the target type's maximum throws an error.
    ///
    /// This uses our helper function `testOversizedInteger` for various integer types.
    func testOversizedIntegers() {
        testOversizedInteger(type: Int.self)
        testOversizedInteger(type: Int8.self)
        testOversizedInteger(type: Int16.self)
        testOversizedInteger(type: Int32.self)
        testOversizedInteger(type: Int64.self)
        testOversizedInteger(type: UInt.self)
        testOversizedInteger(type: UInt8.self)
        testOversizedInteger(type: UInt16.self)
        testOversizedInteger(type: UInt32.self)
        testOversizedInteger(type: UInt64.self)
    }
    
    // MARK: - Floating-Point Number Tests

    /// Tests decoding for various floating-point types.
    ///
    /// These tests verify that encoding then decoding (isomorphism) works for floating-point numbers.
    func testFloatingPointNumbers() {
        testDecoding(for: Float.self)
        testDecoding(for: Float32.self)
        testDecoding(for: Float64.self)
        testDecoding(for: CGFloat.self)
        testDecoding(for: Double.self)
        testDecoding(for: Decimal.self)
    }
    
    // MARK: - Generic Decoder Tests

    /// Runs a series of decoding tests for a variety of common types.
    func testDecoder() {
        testDecoding(for: Date.self, dateStrategy: [
            (.deferredToDate, .deferredToDate),
            (.secondsSince1970, .secondsSince1970),
            (.millisecondsSince1970, .millisecondsSince1970),
            (.iso8601, .iso8601)
        ])
        testDecoding(for: Data.self, dataStrategy: [
            (.deferredToData, .deferredToData),
            (.base64, .base64)
        ])
        testDecoding(for: Bool.self)
        testDecoding(for: Int.self)
        testDecoding(for: Int8.self)
        testDecoding(for: Int16.self)
        testDecoding(for: Int32.self)
        testDecoding(for: Int64.self)
        testDecoding(for: UInt.self)
        testDecoding(for: UInt8.self)
        testDecoding(for: UInt16.self)
        testDecoding(for: UInt32.self)
        testDecoding(for: UInt64.self)
        testDecoding(for: String.self)
    }
}
