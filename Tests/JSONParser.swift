//
//  JSONParser.swift
//  MonadicJSON macOS
//
//  Created by Charlotte Tortorella on 18/4/19.
//

import XCTest
import SwiftCheck
@testable import MonadicJSON

let encoder = JSONEncoder()
// Change this `false` to view failures of the inbuilt decoder.
#if true
let decoder = MonadicJSONDecoder()
#else
let decoder = Foundation.JSONDecoder()
#endif

class JSONTests: XCTestCase {
    func testParserGenerally() {
        property("Random strings can't crash the parser") <- forAll { (string: String) in
            _ = JSONParser.parse(string)
            return true
        }
    }
    
    func testStrings() {
        property("Strings are all valid") <- forAll(strings) { string in
            JSONParser.parseString(string).succeeded
        }
        
        property("Strings are invalid if they don't start/end with '\"'") <- forAll(invalidStrings) { string in
            JSONParser.parseString(string).failed
        }
        
        property("Unicode with 4 hex digits is valid") <- forAllNoShrink(validUnicode) { (args: (scalar: UInt32, string: String)) in
            JSONParser.parseString(args.string).success!.unicodeScalars.first!.value == args.scalar
        }
        
        property("Unicode can occur multiple times in a string") <- forAllNoShrink(validUnicode.map { String($1.dropFirst().dropLast()) }.proliferate) {
            return JSONParser.parseString(["\"", $0.joined(), "\""].joined()).succeeded
        }
        
        property("Unicode with less than 4 hex digits is invalid") <- forAllNoShrink(Gen.zip(validUnicode.map { $1 }, .fromElements(in: (2...5))).map { [String($0.dropLast($1)), "\""].joined() }) { string in
            switch JSONParser.parseString(string).failure {
            case .malformedUnicode?:
                return true
            default:
                return false
            }
        }
        
        property("Unrepresentable unicode is invalid") <- forAllNoShrink(invalidUnicode) { string in
            switch JSONParser.parseString(string).failure {
            case .malformedUnicode?:
                return true
            default:
                return false
            }
        }
        
        property("An array of strings can be repeatedly parsed with the same index until they reach the end") <- forAllNoShrink(strings.proliferate) { strings in
            var index = 0
            let joined = strings.joined()
            let s = Array(joined.unicodeScalars)
            return
                (0..<strings.count).allSatisfy { JSONParser.parseString(scalars: s, index: &index).success == strings[$0].reified } <?> "All strings parsed"
                    ^&&^
                    (index == s.endIndex) <?> "index == endIndex"
        }
    }
    
    func testDictionaries() {
        property("Dictionaries are all valid") <- forAllNoShrink(dictionaries) { string in
            return JSONParser.parse(string).succeeded
        }
        
        property("Dictionaries containing invalid strings are invalid") <- forAllNoShrink(dictionary(invalidAlphabetical, invalidAlphabetical)) { string in
            JSONParser.parse(string).failed
        }
        
        property("Dictionaries that are unterminated will result in a malformed error") <- forAllNoShrink(Gen.pure("[{\"\":").proliferateNonEmpty) { strings in
            switch JSONParser.parse(strings.joined()).failure {
            case .dictionary(.malformed)?:
                return true
            default:
                return false
            }
        }
    }
    
    func testArrays() {
        property("Arrays are all valid") <- forAllNoShrink(arrays) { string in
            JSONParser.parse(string).succeeded
        }
        
        property("Arrays containing invalid strings are invalid") <- forAllNoShrink(array(invalidAlphabetical)) { string in
            JSONParser.parse(string).failed
        }
        
        property("Arrays can handle arbitrary nesting levels") <- forAllNoShrink(Gen.pure("[").proliferateNonEmpty.map { $0.joined() }) { string in
            switch JSONParser.parse(string).failure {
            case .array(.malformed)?:
                return true
            default:
                return false
            }
        }
        
        property("Unterminated arrays will result in malformed errors") <- forAllNoShrink(Gen.one(of: [strings, randomNumbers, arrays, dictionaries]).map { "[" + $0 }) { string in
            switch JSONParser.parse(string).failure {
            case .array(.malformed)?:
                return true
            default:
                return false
            }
        }
    }
    
    func testNumbers() {
        property("Numbers are all valid") <- forAll(randomNumbers) { (string: String) in
            JSONParser.parse(string).success == .number(string)
        }
        
        property("Numbers that begin with 0 are invalid") <- forAll(invalidJsonNumbers) { (string: String) in
            JSONParser.parse(string).failure == .number(.numberBeginningWithZero(index: 0))
        }
        
        property("NaN is invalid") <- forAll(Gen.pure("NaN").maybeCapitalized) { (string: String) in
            JSONParser.parse(string).failed
        }
    }
    
    func testBools() {
        property("Bools are all valid") <- forAll { (bool: Bool) in
            JSONParser.parse(bool.description).success == .bool(bool)
        }
        
        property("Capitalised bools are invalid") <- forAll(Bool.arbitrary.map { $0.description }.maybeCapitalized) { string in
            return (![true, false].contains(where: { $0.description == string })) ==> {
                JSONParser.parse(string).failed
            }
        }
    }
    
    func testNull() {
        property("Null is valid") <- forAllNoShrink(.pure(())) { _ in
            JSONParser.parse("null").succeeded
        }
        
        property("Capitalised nulls are invalid") <- forAll(Gen.pure("null").maybeCapitalized) { string in
            return (string != "null") ==> {
                JSONParser.parse(string).failed
            }
        }
    }
    
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
    
    func testFloatingPointNumbers() {
        testDecoding(for: Float.self)
        testDecoding(for: Float32.self)
        testDecoding(for: Float64.self)
        testDecoding(for: CGFloat.self)
        testDecoding(for: Double.self)
        testDecoding(for: Decimal.self)
    }
    
    func testDecoder() {
        testDecoding(for: Date.self, dateStrategy: [
            (.deferredToDate, .deferredToDate),
            (.secondsSince1970, .secondsSince1970),
            (.millisecondsSince1970, .millisecondsSince1970),
            (.iso8601, .iso8601)
            ]
        )
        testDecoding(for: Data.self, dataStrategy: [
            (.deferredToData, .deferredToData),
            (.base64, .base64)
            ]
        )
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
