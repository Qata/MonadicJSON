import Foundation
import SwiftCheck
@testable import MonadicJSON

// MARK: - Composite Type for Testing

/// A typealias that combines Codable, Arbitrary, and Equatable requirements.
/// Any type conforming to CodableArbitrary can be encoded/decoded,
/// can be randomly generated using SwiftCheck, and supports equality testing.
typealias CodableArbitrary = Codable & Arbitrary & Equatable

// MARK: - Integer Protocol for Testing Oversized Integers

/// A protocol for integer types used in testing.
/// It extends Codable, Arbitrary, and BinaryInteger so that integer types can be
/// encoded/decoded, randomly generated, and used in arithmetic/comparison operations.
/// Additionally, it requires a `max` property to test for overflow/oversized values.
protocol Integer: Codable, Arbitrary, BinaryInteger {
    static var max: Self { get }
}

// MARK: - Decoding Type Enumeration

/// An enumeration representing different kinds of JSON structures that can be decoded.
/// It is used to randomly select between arrays, nested arrays, objects, or nested objects,
/// so that tests can cover a variety of JSON structures.
enum DecodingType: Arbitrary, CaseIterable {
    case array
    case nestedArray
    case object
    case nestedObject
    
    /// A generator that randomly selects one of the available decoding types.
    /// By using `allCases` (provided by CaseIterable), SwiftCheck can generate a random value.
    static var arbitrary: Gen<DecodingType> {
        .fromElements(of: allCases)
    }
}

// MARK: - Decoder Test Wrapper

/// A helper structure used to wrap any value of a type that conforms to CodableArbitrary.
/// This is particularly useful when testing encoding and decoding operations:
/// the value is encoded into JSON and then decoded back, and then compared to the original.
///
/// Conforms to Equatable (so we can compare the decoded value to the original),
/// Codable (so it can be encoded/decoded), and Arbitrary (so random instances can be generated).
struct DecoderTest<T: CodableArbitrary>: Equatable, Codable, Arbitrary {
    let value: T
    
    /// A generator for DecoderTest instances.
    /// It creates a random value of type T and wraps it in a DecoderTest.
    static var arbitrary: Gen<DecoderTest<T>> {
        T.arbitrary.map(DecoderTest.init(value:))
    }
}
