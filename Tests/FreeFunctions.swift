//
//  FreeFunctions.swift
//  MonadicJSON
//
//  Created by Charlotte Tortorella on 23/4/19.
//

import Foundation
import SwiftCheck
@testable import MonadicJSON

func yield<T>(_ closure: () -> T) -> T {
    return closure()
}

func testDecoding<T: CodableArbitrary>(for type: T.Type = T.self, decoder: TopLevelDecoder = MonadicJSONDecoder(), gen: Gen<T> = T.arbitrary, dateStrategy: [(JSONEncoder.DateEncodingStrategy, JSONDecoder.DateDecodingStrategy)] = [(.deferredToDate, .deferredToDate)], dataStrategy: [(JSONEncoder.DataEncodingStrategy, JSONDecoder.DataDecodingStrategy)] = [(.deferredToData, .deferredToData)], transform: @escaping (Property) -> Property = { $0 }) {
    let ((dateEncoding, dateDecoding), (dataEncoding, dataDecoding)) = Gen.zip(.fromElements(of: dateStrategy), .fromElements(of: dataStrategy)).generate
    encoder.dateEncodingStrategy = dateEncoding
    encoder.dataEncodingStrategy = dataEncoding
    decoder.setDateDecodingStrategy(dateDecoding)
    decoder.setDataDecodingStrategy(dataDecoding)
    property("\(T.self) is valid for all permutations") <- transform(
        conjoin(
            decodeProperty(decoder: decoder, gen: gen),
            decodeProperty(decoder: decoder, gen: gen.map { Optional($0) }),
            yield {
                let dictionaryGen = Gen
                    .zip(String.arbitrary, gen)
                    .proliferate
                    .map { Dictionary($0, uniquingKeysWith: { $1 }) }
                switch DecodingType.arbitrary.generate {
                case .array:
                    return decodeProperty(decoder: decoder, gen: gen.proliferate)
                case .nestedArray:
                    return decodeProperty(decoder: decoder, gen: gen.proliferate.proliferate)
                case .dictionary:
                    return decodeProperty(decoder: decoder, gen: dictionaryGen)
                case .nestedDictionary:
                    return decodeProperty(decoder: decoder, gen:
                        Gen
                            .zip(String.arbitrary, dictionaryGen)
                            .proliferate
                            .map { Dictionary($0, uniquingKeysWith: { $1 }) }
                    )
                }
            }
        )
    )
}

func decodeProperty<T: CodableArbitrary>(decoder: TopLevelDecoder, gen: Gen<T>) -> Property {
    print("*** Starting isomorphism tests for \(T.self) decoding")
    return forAllNoShrink(gen) {
        let label = "Isomorphic \(T.self) decode"
        let value = try! decoder.decode(DecoderTest<T>.self, from: data($0)).value
        return (value == $0) <?> label
    }
}

func testOversizedInteger<T: Integer>(type: T.Type, decoder: TopLevelDecoder = MonadicJSONDecoder()) {
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

func data<T: CodableArbitrary>(_ value: T) -> Data {
    return try! encoder.encode(DecoderTest<T>(value: value))
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
