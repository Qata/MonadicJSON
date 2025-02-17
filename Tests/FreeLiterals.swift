import Foundation
import SwiftCheck
@testable import MonadicJSON

/// A global JSONEncoder instance used by tests for encoding values.
let encoder = JSONEncoder()

/// An array of known “broken” decimal strings.
/// These decimals are known to cause issues with certain JSON decoders,
/// which is useful when comparing behavior between different decoders.
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

/// A set of Unicode scalars representing common whitespace and newline characters.
/// These are used to “envelop” JSON components with extra formatting.
let whitespacesAndNewlines: Set<UnicodeScalar> = [
    "\n",
    "\t",
    " ",
    "\r"
]

/// A generator for strings consisting solely of numeric characters ("0"–"9").
/// This is achieved by filtering arbitrary Unicode scalars to only include digits,
/// then proliferating them into a sequence and converting that sequence into a string.
let allNumbers = UnicodeScalar.arbitrary
    .suchThat { CharacterSet(charactersIn: "0"..."9").contains($0) }
    .proliferate
    .string

/// A generator for valid JSON integer strings.
/// It generates either a non-zero integer (a digit between "1" and "9" followed by
/// an optional sequence of digits) or the string "0".
let integers = Gen.one(of: [
    .zipWith(
        // Generate a non-zero first digit.
        Gen.fromElements(of: UnicodeScalar.allScalars(from: "1", through: "9")
            .map { String(Character($0)) }
        ),
        // With a chance to append additional digits (or not).
        .frequency([(3, allNumbers), (1, .pure(""))]),
        transform: +
    ),
    // Or simply "0".
    .pure("0")
])

/// A generator that builds components of a JSON number as an array of strings.
/// The array contains parts such as the sign, integer part, fractional part, and exponent.
/// Each component is optionally generated, and empty strings represent missing parts.
let jsonNumbers: Gen<[String]> = .compose { c in
    // Generate a minus sign or an empty string.
    let minus = Gen<String>.fromElements(of: ["-", ""])
    
    // Optionally generate a fractional part: if chosen, prepend a "." and append a non-empty sequence of digits.
    let fractional = c.generate(using: Gen<String?>.fromElements(of: [".", nil]))
        .map { fractionSymbol in
            [fractionSymbol, c.generate(using: allNumbers.suchThat { !$0.isEmpty })].joined()
        }
        ?? ""
    
    // Optionally generate an exponent part: if chosen, start with "e" or "E", include a sign, and then an integer.
    let exponential = c.generate(using: Gen<String?>.fromElements(of: ["e", "E", nil]))
        .map { expSymbol in
            [
                expSymbol,
                c.generate(
                    using: Gen<String>.fromElements(
                        of: [
                            "+", 
                            "-", 
                            ""
                        ]
                    )
                ),
                c.generate(using: integers)
            ].joined()
        }
        ?? ""
    
    // Return the components as an array: [sign, integer, fractional, exponential].
    return [
        c.generate(using: minus),
        c.generate(using: integers),
        fractional,
        exponential
    ]
}

/// A generator for invalid JSON number strings.
/// It modifies the output of `jsonNumbers` by inserting a "0" in a wrong place,
/// creating a number string that doesn't comply with JSON number formatting rules.
let invalidJsonNumbers: Gen<String> = jsonNumbers.map {
    // Reconstruct the number string while forcefully inserting an extra "0" after the first component.
    [
        $0.prefix(1),
        ["0"],
        $0.dropFirst()
    ].joined().joined()
}

/// A generator for random JSON number strings.
/// It selects one of several strategies: constructing a number from components,
/// or using Swift's standard representations of Double, Int, or Float.
let randomNumbers: Gen<String> = .one(of: [
    // Build a number by joining the components from `jsonNumbers`.
    jsonNumbers.map { $0.joined() },
    // Or use the string description of a randomly generated Double.
    Double.arbitrary.map(\.description),
    // Or an Int.
    Int.arbitrary.map(\.description),
    // Or a Float.
    Float.arbitrary.map(\.description)
])

/// A generator for valid Unicode escapes in JSON.
/// Uses the `unicode(suchThat:)` helper to produce a tuple of the scalar value
/// and its corresponding JSON Unicode escape string.
let validUnicode = unicode(suchThat: { UnicodeScalar($0) != nil })

/// A generator for invalid Unicode escapes.
/// It selects Unicode scalars that cannot be represented properly (i.e. where `UnicodeScalar($0)` is nil)
/// and maps the tuple to just the escaped string.
let invalidUnicode = unicode(suchThat: { UnicodeScalar($0) == nil }).map { $1 }

/// A generator for valid JSON string literals.
/// It starts with an arbitrary Swift String and then encodes it (adding quotes and escape characters)
/// to match JSON string formatting.
let strings: Gen<String> = String.arbitrary.map(\.encoded)

/// A generator for invalid JSON string literals.
/// It takes valid JSON strings and deliberately removes the starting quote,
/// the ending quote, or both—making them invalid as JSON strings.
let invalidStrings: Gen<String> = strings
    .ap(.fromElements(of: [
        { $0.dropFirst() },  // Remove the starting quote.
        { $0.dropLast() },   // Remove the ending quote.
        { $0.dropFirst().dropLast() } // Remove both.
    ]))
    .map(String.init)

/// A generator for alphabetical Unicode scalars (letters a–z and A–Z).
let alphabetical: Gen<UnicodeScalar> = Gen.fromElements(of:
    UnicodeScalar.allScalars(from: "a", through: "z") +
    UnicodeScalar.allScalars(from: "A", through: "Z")
)

/// A generator for invalid alphabetical strings.
/// It creates a non-empty sequence of alphabetical Unicode scalars and then
/// prepends an opening quote, simulating a string that is not properly terminated.
let invalidAlphabetical: Gen<String> = alphabetical
    .proliferateNonEmpty
    .string
    .map { "\"" + $0 }

/// A generator for JSON array strings.
/// This generator builds arrays by selecting one of several element types:
/// random numbers, strings, valid Unicode escapes, or JSON dictionaries.
/// The chosen elements are proliferated into an array, and then the `array` helper
/// (defined elsewhere) formats them as a JSON array string.
let arrays = array(
    Gen.one(of: [
        randomNumbers,
        strings,
        validUnicode.map { $1 },
        // Build a dictionary with keys from either strings or valid Unicode escapes,
        // and values from random numbers, strings, or valid Unicode escapes.
        dictionary(
            Gen.one(of: [strings, validUnicode.map { $1 }]).proliferate,
            Gen.one(of: [randomNumbers, strings, validUnicode.map { $1 }]).proliferate
        )
    ]).proliferate
)

/// A generator for JSON object (dictionary) strings.
/// The keys are generated from either valid JSON strings or valid Unicode escapes,
/// while the values can be random numbers, strings, valid Unicode escapes, or arrays.
/// The `dictionary` helper (defined elsewhere) is then used to format them as a JSON object.
let dictionaries = dictionary(
    // Generate keys.
    Gen.one(of: [strings, validUnicode.map { $1 }]).proliferate,
    // Generate values.
    Gen.one(of: [
        randomNumbers,
        strings,
        validUnicode.map { $1 },
        array(Gen.one(of: [randomNumbers, strings, validUnicode.map { $1 }]).proliferate)
    ]).proliferate
)
