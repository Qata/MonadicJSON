import Foundation
import SwiftCheck
@testable import MonadicJSON

/// A helper function to “yield” a value from a closure.
/// This can be useful to delay evaluation or to improve readability when composing generators.
func yield<T>(_ closure: () -> T) -> T {
    return closure()
}

/// Runs decoding tests on any type that conforms to CodableArbitrary.
/// It verifies that a value, when encoded and then decoded, matches the original value.
/// Additionally, it tests various encoding/decoding strategy permutations.
///
/// - Parameters:
///   - type: The type to be tested (default inferred).
///   - decoder: The decoder used for testing (default is MonadicJSONDecoder).
///   - gen: A generator for random instances of the type.
///   - dateStrategy: A list of date encoding/decoding strategy pairs to choose from.
///   - dataStrategy: A list of data encoding/decoding strategy pairs to choose from.
///   - transform: An optional transformation applied to the generated property (default is identity).
func testDecoding<T: CodableArbitrary>(
    for type: T.Type = T.self,
    decoder: TopLevelDecoder = MonadicJSONDecoder(),
    gen: Gen<T> = T.arbitrary,
    dateStrategy: [(JSONEncoder.DateEncodingStrategy, JSONDecoder.DateDecodingStrategy)] = [(.deferredToDate, .deferredToDate)],
    dataStrategy: [(JSONEncoder.DataEncodingStrategy, JSONDecoder.DataDecodingStrategy)] = [(.deferredToData, .deferredToData)],
    transform: @escaping (Property) -> Property = { $0 }
) {
    // Randomly select a date strategy and a data strategy using SwiftCheck generators.
    let ((dateEncoding, dateDecoding), (dataEncoding, dataDecoding)) =
        Gen.zip(.fromElements(of: dateStrategy), .fromElements(of: dataStrategy)).generate

    // Configure the global encoder with the selected strategies.
    encoder.dateEncodingStrategy = dateEncoding
    encoder.dataEncodingStrategy = dataEncoding
    
    // Configure the decoder with the corresponding strategies.
    decoder.setDateDecodingStrategy(dateDecoding)
    decoder.setDataDecodingStrategy(dataDecoding)
    
    // Compose a property that conjoins several decoding tests.
    // The property ensures that the encoded/decoded value is isomorphic to the original.
    property("\(T.self) is valid for all permutations") <- transform(
        conjoin(
            // Test decoding for non-optional values.
            decodeProperty(decoder: decoder, gen: gen),
            // Test decoding for optional values.
            decodeProperty(decoder: decoder, gen: gen.map { Optional($0) }),
            // Use yield to defer creation of an additional test property.
            yield {
                // Create a generator for dictionaries with String keys and T values.
                let dictionaryGen = Gen
                    .zip(String.arbitrary, gen)
                    .proliferate
                    .map { Dictionary($0, uniquingKeysWith: { $1 }) }
                // Based on a randomly generated decoding type, run different tests:
                switch DecodingType.arbitrary.generate {
                case .array:
                    // Test decoding of an array of T values.
                    return decodeProperty(decoder: decoder, gen: gen.proliferate)
                case .nestedArray:
                    // Test decoding of a nested array (array of arrays) of T values.
                    return decodeProperty(decoder: decoder, gen: gen.proliferate.proliferate)
                case .object:
                    // Test decoding of a dictionary where values are of type T.
                    return decodeProperty(decoder: decoder, gen: dictionaryGen)
                case .nestedObject:
                    // Test decoding of a nested dictionary (object within an object).
                    return decodeProperty(
                        decoder: decoder,
                        gen: Gen.zip(String.arbitrary, dictionaryGen)
                            .proliferate.map {
                                Dictionary($0, uniquingKeysWith: { $1 })
                            }
                    )
                }
            }
        )
    )
}

/// Creates a property that tests isomorphism for decoding.
/// For every generated instance of T, the function encodes and then decodes it,
/// ensuring that the final value equals the original.
///
/// - Parameters:
///   - decoder: The TopLevelDecoder used for decoding.
///   - gen: A generator producing random instances of T.
/// - Returns: A Property that passes if decoding is isomorphic.
func decodeProperty<T: CodableArbitrary>(decoder: TopLevelDecoder, gen: Gen<T>) -> Property {
    // Print a log message for debugging purposes.
    print("*** Starting isomorphism tests for \(T.self) decoding")
    
    // For each generated value, encode and decode it, then compare to the original.
    return forAllNoShrink(gen) { original in
        let label = "Isomorphic \(T.self) decode"
        // Encode the value wrapped in DecoderTest and then decode it back.
        let value = try! decoder.decode(DecoderTest<T>.self, from: data(original)).value
        // The test property asserts that the decoded value equals the original.
        return (value == original) <?> label
    }
}

/// Tests that attempting to decode an integer larger than the target type's maximum throws an error.
///
/// - Parameters:
///   - type: The integer type to test.
///   - decoder: The TopLevelDecoder used for decoding (default is MonadicJSONDecoder).
func testOversizedInteger<T: Integer>(type: T.Type, decoder: TopLevelDecoder = MonadicJSONDecoder()) {
    // Create a property test that generates oversized numbers (greater than T.max)
    property("Oversized integer instantiation will always throw an error") <- forAll(
        // Generate a Double from valid integer strings that are too large for T.
        integers.filterMap(Double.init).suchThat { $0 > Double(T.max) }
    ) { value in
        do {
            // Try to decode the oversized value.
            _ = try decoder.decode(DecoderTest<T>.self, from: data(value))
        } catch let error as DecodingError {
            // If a DecodingError is thrown, check if its description matches the expected format.
            switch error {
            case let .dataCorrupted(context):
                let description = context.debugDescription
                return description.hasPrefix("Parsed JSON number <") &&
                       description.hasSuffix("> does not fit in \(T.self).")
            default:
                break
            }
        }
        // If no error or an unexpected error occurs, the test fails.
        return false
    }
}

/// Encodes a value of type T (wrapped in DecoderTest) into Data using a global encoder.
/// This function is used to simulate the encoding process before decoding tests.
///
/// - Parameter value: The value to encode.
/// - Returns: The encoded Data.
func data<T: CodableArbitrary>(_ value: T) -> Data {
    return try! encoder.encode(DecoderTest<T>(value: value))
}

/// Generates a tuple containing a Unicode scalar (UInt32) and its JSON escape representation.
/// The generated escape string follows the JSON Unicode escape format.
///
/// - Parameter predicate: A filter predicate to restrict which Unicode scalars are generated.
/// - Returns: A generator producing a tuple of (scalar, escaped string).
func unicode(suchThat predicate: @escaping (UInt32) -> Bool) -> Gen<(UInt32, String)> {
    return Gen
        // Generate Unicode scalar values in the range 0x1000 to 0xFFFF.
        .fromElements(in: 0x1000...0xFFFF)
        .suchThat(predicate)
        // Combine the scalar with a formatting function that randomly chooses "x" or "X"
        // This gives us either upper or lowercase hex.
        .ap(
            Gen.fromElements(
                of: ["x", "X"]
            ).map { fmt in
                // The closure formats the scalar using the specified format.
                { (scalar: UInt32) in (scalar, String(format: "%\(fmt)", scalar)) }
            }
        )
        // Map the result into a tuple where the escaped string is wrapped in JSON Unicode escape syntax.
        .map { (scalar, formatted) in (scalar, "\"\\u\(formatted)\"") }
}

/// Constructs a JSON array string from a generator that produces an array of JSON string elements.
///
/// - Parameter values: A generator producing an array of JSON string components.
/// - Returns: A generator producing a formatted JSON array as a string.
func array(_ values: Gen<[String]>) -> Gen<String> {
    return values
        .map { components in
            // Create an array string by surrounding the components with brackets.
            // Elements are separated by commas and enveloped with optional whitespace.
            [
                "[",
                components.intersperse(element: ",")
                    .envelop(whitespacesAndNewlines)
                    .joined(),
                "]"
            ]
            .envelop(whitespacesAndNewlines)
            .joined()
        }
}

/// Constructs a JSON array string from a generator that produces individual JSON string components.
/// This version ensures that the array is non-empty.
///
/// - Parameter values: A generator producing individual JSON string components.
/// - Returns: A generator producing a formatted JSON array as a string.
func array(_ values: Gen<String>) -> Gen<String> {
    return values
        .proliferateNonEmpty
        .map { components in
            [
                "[",
                components.intersperse(element: ",")
                    .envelop(whitespacesAndNewlines)
                    .joined(),
                "]"
            ]
            .envelop(whitespacesAndNewlines)
            .joined()
        }
}

/// Constructs a JSON object (dictionary) string from generators for keys and values.
/// This version takes arrays of keys and values.
///
/// - Parameters:
///   - keys: A generator producing an array of JSON string keys.
///   - values: A generator producing an array of JSON string values.
/// - Returns: A generator producing a formatted JSON object as a string.
func dictionary(_ keys: Gen<[String]>, _ values: Gen<[String]>) -> Gen<String> {
    return Gen
        .zip(keys, values)
        .map { (keysArray, valuesArray) in
            [
                "{",
                // Zip keys and values into key-value pairs.
                zip(keysArray, valuesArray)
                    .map { key, value in
                        [key, ":", value]
                            .envelop(whitespacesAndNewlines)
                            .joined()
                    }
                    .intersperse(element: ",")
                    .envelop(whitespacesAndNewlines)
                    .joined(),
                "}"
            ]
            .joined()
        }
}

/// Constructs a JSON object (dictionary) string from generators that produce individual keys and values.
/// This version ensures that at least one key-value pair is generated.
///
/// - Parameters:
///   - keys: A generator producing individual JSON string keys.
///   - values: A generator producing individual JSON string values.
/// - Returns: A generator producing a formatted JSON object as a string.
func dictionary(_ keys: Gen<String>, _ values: Gen<String>) -> Gen<String> {
    return Gen
        .zip(keys.proliferateNonEmpty, values.proliferateNonEmpty)
        .map { (keysArray, valuesArray) in
            [
                "{",
                zip(keysArray, valuesArray)
                    .map { key, value in
                        [key, ":", value]
                            .envelop(whitespacesAndNewlines)
                            .joined()
                    }
                    .intersperse(element: ",")
                    .envelop(whitespacesAndNewlines)
                    .joined(),
                "}"
            ]
            .joined()
        }
}
