//
//  FreeLiterals.swift
//  MonadicJSON macOS
//
//  Created by Charlotte Tortorella on 23/4/19.
//

import Foundation
import SwiftCheck
@testable import MonadicJSON

let encoder = JSONEncoder()

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

let validUnicode = unicode(suchThat: { UnicodeScalar($0) != nil })

let invalidUnicode = unicode(suchThat: { UnicodeScalar($0) == nil }).map { $1 }

let strings: Gen<String> = String
    .arbitrary
    .map(\.encoded)

let invalidStrings: Gen<String> = strings
    .ap(.fromElements(of: [{ $0.dropFirst() }, { $0.dropLast() }, { $0.dropFirst().dropLast() }]))
    .map(String.init)

let alphabetical: Gen<UnicodeScalar> = Gen
    .fromElements(of: UnicodeScalar.allScalars(from: "a", through: "z") + UnicodeScalar.allScalars(from: "A", through: "Z"))

let invalidAlphabetical: Gen<String> = alphabetical
    .proliferateNonEmpty
    .string
    .map { "\"" + $0 }

let arrays = array(Gen.one(of: [randomNumbers, strings, validUnicode.map { $1 }, dictionary(Gen.one(of: [strings, validUnicode.map { $1 }]).proliferate, Gen.one(of: [randomNumbers, strings, validUnicode.map { $1 }]).proliferate)]).proliferate)
let dictionaries = dictionary(Gen.one(of: [strings, validUnicode.map { $1 }]).proliferate, Gen.one(of: [randomNumbers, strings, validUnicode.map { $1 }, array(Gen.one(of: [randomNumbers, strings, validUnicode.map { $1 }]).proliferate)]).proliferate)
