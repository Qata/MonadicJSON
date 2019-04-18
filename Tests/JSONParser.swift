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
// Change this `Swift.JSONDecoder` to view failures of the inbuilt decoder.
let decoder = MonadicJSONDecoder()

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
    
    func testDecoder() {
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
        testDecoding(for: Float.self)
        testDecoding(for: Double.self)
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
        testDecoding(for: Decimal.self)
        testDecoding(for: String.self)
    }
}

typealias CodableArbitrary = Codable & Arbitrary & Equatable

protocol Integer: Codable, Arbitrary, BinaryInteger {
    static var max: Self { get }
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

func testOversizedInteger<T: Integer>(type: T.Type) {
    property("Oversized integer instantiation will always throw an error") <- forAll(integers.filterMap(Double.init).suchThat { $0 > Double(T.max) }) { value in
        do {
            _ = try decoder.decode(DecoderTest<T>.self, from: data(value))
        } catch let error as DecodingError {
            switch error {
            case let .dataCorrupted(context):
                let description = context.debugDescription
                return description.hasPrefix("Parsed JSON number <") && description.hasSuffix("> does not fit in \(T.self).")
            default:
                break
            }
        }
        return false
    }
}

func testDecoding<T: CodableArbitrary>(for type: T.Type, dateStrategy: [(JSONEncoder.DateEncodingStrategy, MonadicJSONDecoder.DateDecodingStrategy)] = [(.deferredToDate, .deferredToDate)], dataStrategy: [(JSONEncoder.DataEncodingStrategy, MonadicJSONDecoder.DataDecodingStrategy)] = [(.deferredToData, .deferredToData)]) {
    let ((dateEncoding, dateDecoding), (dataEncoding, dataDecoding)) = Gen.zip(.fromElements(of: dateStrategy), .fromElements(of: dataStrategy)).generate
    encoder.dateEncodingStrategy = dateEncoding
    encoder.dataEncodingStrategy = dataEncoding
    decoder.dateDecodingStrategy = dateDecoding
    decoder.dataDecodingStrategy = dataDecoding
    _testDecoding(for: T.self)
    _testDecoding(for: Optional<T>.self)
    switch DecodingType.arbitrary.generate {
    case .array:
        _testDecoding(for: [T].self)
    case .nestedArray:
        _testDecoding(for: [[T]].self)
    case .dictionary:
        _testDecoding(for: [String: T].self)
    case .nestedDictionary:
        _testDecoding(for: [String: [String: T]].self)
    }
}

func _testDecoding<T: CodableArbitrary>(for type: T.Type, _ gen: Gen<T> = T.arbitrary) {
    property("\(T.self) is valid for all permutations") <- decodeProperty(containing: T.self, gen)
}

enum DecodingType: Arbitrary, CaseIterable {
    case array
    case nestedArray
    case dictionary
    case nestedDictionary
    
    static var arbitrary: Gen<DecodingType> {
        return .fromElements(of: allCases)
    }
}

func decodeProperty<T: CodableArbitrary>(containing type: T.Type, _ gen: Gen<T>) -> Property {
    print("*** Starting isomorphism tests for \(T.self) decoding")
    return forAllNoShrink(gen) {
        let label = "Isomorphic \(T.self) decode"
        let value = try! decoder.decode(DecoderTest<T>.self, from: data($0)).value
        if value == $0 {
            return true <?> label
        } else {
            print("Value before parsing: <\($0)>, after: <\(value)>")
            return false <?> label
        }
    }
}

func data<T: CodableArbitrary>(_ value: T) -> Data {
    return try! encoder.encode(DecoderTest<T>(value: value))
}

struct DecoderTest<T: CodableArbitrary>: Equatable, Codable, Arbitrary {
    let value: T
    
    static var arbitrary: Gen<DecoderTest<T>> {
        return .compose { .init(value: $0.generate()) }
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
    var maybeCapitalized: Gen {
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
        return Array(zip(self, (0...numericCast(count)).map { _ in gen.generate }).flatMap { [$0, $1] }.dropLast())
    }
    
    func envelop(_ gen: Gen<Element>) -> [Element] {
        return Array([[gen.generate], intersperse(gen), [gen.generate]].joined())
    }
}

extension Collection where Element == String {
    func envelop(_ set: CharacterSet) -> [String] {
        let characters = Array(0..<0xFF).compactMap(UnicodeScalar.init).filter(set.contains)
        let gen = Gen.fromElements(of: characters).map(Character.init)
        return envelop(UInt.arbitrary.map { String(repeating: gen.generate, count: numericCast($0)) })
    }
}

extension JSONParser {
    static func parse(_ string: String) -> Result<JSON, JSONParser.Error> {
        return JSONParser.parse(data: string.data(using: .utf8)!)
    }
    
    static func parseString(_ string: String) -> Result<String, JSONParser.Error.String> {
        var index = 0
        return JSONParser.parseString(scalars: Array(string.unicodeScalars), index: &index)
    }
}

let allNumbers = UnicodeScalar.arbitrary.suchThat(CharacterSet(charactersIn: "0"..."9").contains).proliferate.string

let integers = Gen.one(of: [
    Gen.zip(UnicodeScalar.arbitrary.suchThat(CharacterSet(charactersIn: "1"..."9").contains).map { String(Character($0)) }, .frequency([(3, allNumbers), (1, .pure(""))])).map(+),
    .pure("0")
    ]
)

let jsonNumbers: Gen<[String]> = .compose { c in
    let minus = Gen<String>.fromElements(of: ["-", ""])
    let plusMinus = Gen<String>.fromElements(of: ["+", "-", ""])
    
    let fractional = c.generate(using: Gen<String?>.fromElements(of: [".", nil]))
        .map { [$0, c.generate(using: allNumbers.suchThat { !$0.isEmpty })].joined() }
        ?? ""
    let exponential = c.generate(using: Gen<String?>.fromElements(of: ["e", "E", nil]))
        .map { [$0, c.generate(using: Gen<String>.fromElements(of: ["+", "-", ""])), c.generate(using: integers)].joined() }
        ?? ""
    return [c.generate(using: minus), c.generate(using: integers), fractional, exponential]
}

let invalidJsonNumbers: Gen<String> = jsonNumbers.map { [$0.prefix(1), ["0"], $0.dropFirst()].joined().joined() }

let randomNumbers: Gen<String> = .one(of: [
    jsonNumbers.map { $0.joined() },
    Double.arbitrary.map(\.description),
    Int.arbitrary.map(\.description),
    Float.arbitrary.map(\.description)
    ])

func unicode(suchThat predicate: @escaping (UInt32) -> Bool) -> Gen<(UInt32, String)> {
    return Gen
        .fromElements(in: 0x1000...0xFFFF)
        .suchThat(predicate)
        .ap(Gen.fromElements(of: ["x", "X"]).map { fmt in { ($0, String(format: "%\(fmt)", $0)) } })
        .map { ($0, "\"\\u\($1)\"") }
}

let validUnicode = unicode(suchThat: { UnicodeScalar($0) != nil })

let invalidUnicode = unicode(suchThat: { UnicodeScalar($0) == nil }).map { $1 }

let strings: Gen<String> = String
    .arbitrary
    .map(\.encoded)

let invalidStrings: Gen<String> = strings
    .ap(.fromElements(of: [{ $0.dropFirst() }, { $0.dropLast() }, { $0.dropFirst().dropLast() }]))
    .map(String.init)

let invalidAlphabetical: Gen<String> = Gen
    .fromElements(of: UnicodeScalar.allScalars(from: "a", through: "z") + UnicodeScalar.allScalars(from: "A", through: "Z"))
    .proliferateNonEmpty
    .string
    .map { "\"" + $0 }

let arrays = array(Gen.one(of: [randomNumbers, strings, validUnicode.map { $1 }, dictionary(Gen.one(of: [strings, validUnicode.map { $1 }]).proliferate, Gen.one(of: [randomNumbers, strings, validUnicode.map { $1 }]).proliferate)]).proliferate)
let dictionaries = dictionary(Gen.one(of: [strings, validUnicode.map { $1 }]).proliferate, Gen.one(of: [randomNumbers, strings, validUnicode.map { $1 }, array(Gen.one(of: [randomNumbers, strings, validUnicode.map { $1 }]).proliferate)]).proliferate)

func array(_ values: Gen<[String]>) -> Gen<String> {
    return values
        .map { ["[", $0.intersperse(element: ",").envelop(.whitespacesAndNewlines).joined(), "]"].envelop(.whitespacesAndNewlines).joined() }
}

func array(_ values: Gen<String>) -> Gen<String> {
    return values
        .proliferateNonEmpty
        .map { ["[", $0.intersperse(element: ",").envelop(.whitespacesAndNewlines).joined(), "]"].envelop(.whitespacesAndNewlines).joined() }
}

func dictionary(_ keys: Gen<[String]>, _ values: Gen<[String]>) -> Gen<String> {
    return Gen
        .zip(keys, values)
        .map { ["{", zip($0, $1).map { [$0, ":", $1].envelop(.whitespacesAndNewlines).joined() }.intersperse(element: ",").envelop(.whitespacesAndNewlines).joined(), "}"].joined() }
}

func dictionary(_ keys: Gen<String>, _ values: Gen<String>) -> Gen<String> {
    return Gen
        .zip(keys.proliferateNonEmpty, values.proliferateNonEmpty)
        .map { ["{", zip($0, $1).map { [$0, ":", $1].envelop(.whitespacesAndNewlines).joined() }.intersperse(element: ",").envelop(.whitespacesAndNewlines).joined(), "}"].joined() }
}

let escapes = [("\\", "\\\\"), ("\"", "\\\"")]

extension String {
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
