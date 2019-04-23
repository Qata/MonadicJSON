//
//  FreeFunctions.swift
//  MonadicJSON
//
//  Created by Charlotte Tortorella on 23/4/19.
//

import Foundation
import SwiftCheck
@testable import MonadicJSON

func testDecoding<T: CodableArbitrary>(for type: T.Type, dateStrategy: [(JSONEncoder.DateEncodingStrategy, MonadicJSONDecoder.DateDecodingStrategy)] = [(.deferredToDate, .deferredToDate)], dataStrategy: [(JSONEncoder.DataEncodingStrategy, MonadicJSONDecoder.DataDecodingStrategy)] = [(.deferredToData, .deferredToData)]) {
    let ((dateEncoding, dateDecoding), (dataEncoding, dataDecoding)) = Gen.zip(.fromElements(of: dateStrategy), .fromElements(of: dataStrategy)).generate
    encoder.dateEncodingStrategy = dateEncoding
    encoder.dataEncodingStrategy = dataEncoding
    decoder.setDateDecodingStrategy(dateDecoding)
    decoder.setDataDecodingStrategy(dataDecoding)
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

func unicode(suchThat predicate: @escaping (UInt32) -> Bool) -> Gen<(UInt32, String)> {
    return Gen
        .fromElements(in: 0x1000...0xFFFF)
        .suchThat(predicate)
        .ap(Gen.fromElements(of: ["x", "X"]).map { fmt in { ($0, String(format: "%\(fmt)", $0)) } })
        .map { ($0, "\"\\u\($1)\"") }
}

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
