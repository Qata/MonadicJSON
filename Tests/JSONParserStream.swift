//
//  JSONParserStream.swift
//  MonadicJSON macOS
//
//  Created by Tiago Janela on 4/29/20.
//

import XCTest
import SwiftCheck
@testable import MonadicJSON

class JSONTestsStream: XCTestCase {
    // Stop using this library if this test fails.
    // This is to test if the problem this library set out to solve has been solved in Foundation.
    func testKnownBrokenDecimals() {
        let brokenDecimals = [
            "57.485767755861504",
            "1.1172404971672576",
            "3.4654083990338176",
            "6.9181938875885312",
            "29.625696350928512",
            "-68.95552528769664",
            "6.1481271341435392",
            "0.3598915583666368",
            "5.4359304839498752",
            "-17.948831098982656",
            "-0.5255438682545152",
            "99.874581495808512",
            "-2.6445110644867712",
            "248.8941461002368",
            "9.0577712447980288",
            "20.874553160971584",
            "-3.5121049544868992",
            "0.76463401787641344",
            "6.849477234107648",
            "2.8994014887784576"
        ]
        let gen = Gen.fromElements(of: brokenDecimals.compactMap { Decimal(string: $0) })

        // JSONDecoder is expected to fail.
        testDecoding(
            decoder: JSONDecoder(),
            gen: gen,
            transform: { $0.expectFailure }
        )
        // MonadicJSONDecoder is expected to succeed.
        testDecoding(
            decoder: MonadicJSONDecoder(useStream: true),
            gen: gen
        )
    }

    func testParserGenerally() {
        property("Random strings can't crash the parser") <- forAll { (string: String) in
            _ = JSONParser.parseStream(string)
            return true
        }
    }

    func testStrings() {
        property("Strings are all valid") <- forAll(strings) { string in
            JSONParser.parseStringStream(string).succeeded
        }

        property("Strings are invalid if they don't start/end with '\"'") <- forAll(invalidStrings) { string in
            JSONParser.parseStringStream(string).failed
        }

        property("Unicode with 4 hex digits is valid") <- forAllNoShrink(validUnicode) { (args: (scalar: UInt32, string: String)) in
            JSONParser.parseStringStream(args.string).success!.unicodeScalars.first!.value == args.scalar
        }

        property("Unicode can occur multiple times in a string") <- forAllNoShrink(validUnicode.map { String($1.dropFirst().dropLast()) }.proliferate) {
            return JSONParser.parseStringStream(["\"", $0.joined(), "\""].joined()).succeeded
        }

        property("Unicode with less than 4 hex digits is invalid") <- forAllNoShrink(Gen.zip(validUnicode.map { $1 }, .fromElements(in: (2...5))).map { [String($0.dropLast($1)), "\""].joined() }) { string in
            switch JSONParser.parseStringStream(string).failure {
            case .malformedUnicode?:
                return true
            default:
                return false
            }
        }

        property("Unrepresentable unicode is invalid") <- forAllNoShrink(invalidUnicode) { string in
            switch JSONParser.parseStringStream(string).failure {
            case .malformedUnicode?:
                return true
            default:
                return false
            }
        }

        property("An array of strings can be repeatedly parsed with the same index until they reach the end") <- forAllNoShrink(strings.proliferate) { strings in
            var index = 0
            let joined = strings.joined()
            let s = String(joined.unicodeScalars)
            let d = s.data(using: .utf8)!
            let i = InputStream(data: d)
            i.open()
            var scalar = i.getNextScalar()
            defer { i.close() }
            return
                (0..<strings.count).allSatisfy {
                    return JSONParser.parseStringStream(stream: i, scalar: &scalar, index: &index).success == strings[$0].reified } <?> "All strings parsed"
                    ^&&^
                    (index == s.count) <?> "index == endIndex"
        }
    }

    func testDictionaries() {
        property("Dictionaries are all valid") <- forAllNoShrink(dictionaries) { string in
            return JSONParser.parseStream(string).succeeded
        }

        property("Dictionaries containing invalid strings are invalid") <- forAllNoShrink(dictionary(invalidAlphabetical, invalidAlphabetical)) { string in
            JSONParser.parseStream(string).failed
        }

        property("Dictionaries that are unterminated will result in a malformed error") <- forAllNoShrink(Gen.pure("[{\"\":").proliferateNonEmpty) { strings in
            switch JSONParser.parseStream(strings.joined()).failure {
            case .dictionary(.malformed)?:
                return true
            default:
                return false
            }
        }
    }

    func testArrays() {
        property("Arrays are all valid") <- forAllNoShrink(arrays) { string in
            JSONParser.parseStream(string).succeeded
        }

        property("Arrays containing invalid strings are invalid") <- forAllNoShrink(array(invalidAlphabetical)) { string in
            JSONParser.parseStream(string).failed
        }

        property("Arrays can handle arbitrary nesting levels") <- forAllNoShrink(Gen.pure("[").proliferateNonEmpty.map { $0.joined() }) { string in
            switch JSONParser.parseStream(string).failure {
            case .array(.malformed)?:
                return true
            default:
                return false
            }
        }

        property("Unterminated arrays will result in malformed errors") <- forAllNoShrink(Gen.one(of: [strings, randomNumbers, arrays, dictionaries]).map { "[" + $0 }) { string in
            switch JSONParser.parseStream(string).failure {
            case .array(.malformed)?:
                return true
            default:
                return false
            }
        }
    }

    func testNumbers() {
        property("Numbers are all valid") <- forAll(randomNumbers) { (string: String) in
            JSONParser.parseStream(string).success == .number(string)
        }

        property("Numbers that begin with 0 are invalid") <- forAll(invalidJsonNumbers) { (string: String) in
            JSONParser.parseStream(string).failure == .number(.numberBeginningWithZero(index: 0))
        }

        property("NaN is invalid") <- forAll(Gen.pure("NaN").randomlyCapitalized) { (string: String) in
            JSONParser.parseStream(string).failed
        }
    }

    func testBools() {
        property("Bools are all valid") <- forAll { (bool: Bool) in
            JSONParser.parseStream(bool.description).success == .bool(bool)
        }

        property("Capitalised bools are invalid") <- forAll(Bool.arbitrary.map { $0.description }.randomlyCapitalized) { string in
            return (![true, false].contains(where: { $0.description == string })) ==> {
                JSONParser.parseStream(string).failed
            }
        }
    }

    func testNull() {
        property("Null is valid") <- forAllNoShrink(.pure(())) { _ in
            JSONParser.parseStream("null").succeeded
        }

        property("Capitalised nulls are invalid") <- forAll(Gen.pure("null").randomlyCapitalized) { string in
            return (string != "null") ==> {
                JSONParser.parseStream(string).failed
            }
        }
    }

    func testOversizedIntegers() {
        testOversizedInteger(type: Int.self, decoder: MonadicJSONDecoder(useStream: true))
        testOversizedInteger(type: Int8.self, decoder: MonadicJSONDecoder(useStream: true))
        testOversizedInteger(type: Int16.self, decoder: MonadicJSONDecoder(useStream: true))
        testOversizedInteger(type: Int32.self, decoder: MonadicJSONDecoder(useStream: true))
        testOversizedInteger(type: Int64.self, decoder: MonadicJSONDecoder(useStream: true))
        testOversizedInteger(type: UInt.self, decoder: MonadicJSONDecoder(useStream: true))
        testOversizedInteger(type: UInt8.self, decoder: MonadicJSONDecoder(useStream: true))
        testOversizedInteger(type: UInt16.self, decoder: MonadicJSONDecoder(useStream: true))
        testOversizedInteger(type: UInt32.self, decoder: MonadicJSONDecoder(useStream: true))
        testOversizedInteger(type: UInt64.self, decoder: MonadicJSONDecoder(useStream: true))
    }

    func testFloatingPointNumbers() {
        testDecoding(for: Float.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: Float32.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: Float64.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: CGFloat.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: Double.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: Decimal.self, decoder: MonadicJSONDecoder(useStream: true))
    }

    func testDecoder() {
        testDecoding(for: Date.self, decoder: MonadicJSONDecoder(useStream: true), dateStrategy: [
            (.deferredToDate, .deferredToDate),
            (.secondsSince1970, .secondsSince1970),
            (.millisecondsSince1970, .millisecondsSince1970),
            (.iso8601, .iso8601)
            ]
        )
        testDecoding(for: Data.self, decoder: MonadicJSONDecoder(useStream: true), dataStrategy: [
            (.deferredToData, .deferredToData),
            (.base64, .base64)
            ]
        )
        testDecoding(for: Bool.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: Int.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: Int8.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: Int16.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: Int32.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: Int64.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: UInt.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: UInt8.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: UInt16.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: UInt32.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: UInt64.self, decoder: MonadicJSONDecoder(useStream: true))
        testDecoding(for: String.self, decoder: MonadicJSONDecoder(useStream: true))
    }
}
