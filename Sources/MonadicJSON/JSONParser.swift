import Foundation

// Core JSON parser and related error definitions.
public struct JSONParser {
    // Categorizes different error types by JSON component.
    public enum Error: Swift.Error, Equatable {
        // Errors encountered while parsing JSON strings.
        public enum String: Swift.Error, Equatable {
            case escapeSequence(index: Int)   // Incomplete escape sequence.
            case escapeCharacter(index: Int)  // Invalid escape character.
            case malformedUnicode(index: Int) // Unicode escape not well-formed.
            case unterminated(index: Int)     // Missing closing quote.
        }
        // Errors encountered while parsing numbers.
        public enum Number: Swift.Error, Equatable {
            case malformed(index: Int)             // Number format error.
            case numberBeginningWithZero(index: Int) // Leading zero not allowed.
        }
        // Errors encountered while parsing booleans.
        public enum Bool: Swift.Error, Equatable {
            case malformed(index: Int) // Boolean literal is invalid.
        }
        // Errors encountered while parsing null.
        public enum Null: Swift.Error, Equatable {
            case malformed(index: Int) // 'null' literal is invalid.
        }
        // Errors encountered while parsing arrays.
        public enum Array: Swift.Error, Equatable {
            case malformed(index: Int) // Array structure is invalid.
        }
        // Errors encountered while parsing dictionaries.
        public enum Dictionary: Swift.Error, Equatable {
            case malformed(index: Int) // Object structure is invalid.
        }
        case empty                          // No content to parse.
        case invalidCharacter(UnicodeScalar, index: Int) // Unexpected character.
        case string(String)                // Wraps string parsing errors.
        case number(Number)                // Wraps number parsing errors.
        case bool(Bool)                    // Wraps boolean parsing errors.
        case null(Null)                    // Wraps null parsing errors.
        case array(Array)                  // Wraps array parsing errors.
        case object(Dictionary)            // Wraps object parsing errors.
    }
    
    // Entry point: converts Data to a Unicode scalar array and starts parsing.
    public static func parse(data: Data) -> Result<JSON, Error> {
        // Fail early if data is not valid UTF-8.
        guard let string = String(data: data, encoding: .utf8) else { return .failure(.empty) }
        var index = 0
        return parse(scalars: Array(string.unicodeScalars), index: &index)
    }
    
    // Recursively parses JSON from an array of UnicodeScalars.
    internal static func parse(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<JSON, Error> {
        while index < scalars.endIndex {
            let scalar = scalars[index]
            // Skip whitespace characters.
            guard !CharacterSet.whitespacesAndNewlines.contains(scalar) else {
                index += 1
                continue
            }
            // Dispatch based on the current token.
            return switch scalar {
            case "{":
                // Parse an object/dictionary.
                parseDictionary(scalars: scalars, index: &index)
                    .map(JSON.object)
            case "[":
                // Parse an array.
                parseArray(scalars: scalars, index: &index)
                    .map(JSON.array)
            case "\"":
                // Parse a string.
                parseString(scalars: scalars, index: &index)
                    .map(JSON.string)
                    .mapError(Error.string)
            case "-", "0"..."9":
                // Parse a number.
                parseNumber(scalars: scalars, index: &index)
                    .map(JSON.number)
                    .mapError(Error.number)
            case "n":
                // Parse the 'null' literal.
                parseNull(scalars: scalars, index: &index)
                    .mapError(Error.null)
            case "t", "f":
                // Parse a boolean literal.
                parseBool(scalars: scalars, index: &index)
                    .map(JSON.bool)
                    .mapError(Error.bool)
            default:
                // Return error for any unexpected token.
                .failure(.invalidCharacter(scalar, index: index))
            }
        }
        return .failure(.empty)
    }
    
    // Parses a JSON object (dictionary) expecting keys as strings and colon-separated values.
    internal static func parseDictionary(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<[String: JSON], Error> {
        let startIndex = index
        // Ensure object starts with '{'
        guard index < scalars.endIndex,
            scalars[index] == "{"
            else { return .failure(.object(.malformed(index: index))) }
        var elements: [String: JSON] = [:]
        index += 1
        while index < scalars.endIndex, scalars[index] != "}" {
            switch scalars[index] {
            // Skip whitespace within the object.
            case _ where CharacterSet.whitespacesAndNewlines.contains(scalars[index]):
                index += 1
            case "\"":
                // Parse key string.
                let key = parseString(scalars: scalars, index: &index).mapError(Error.string)
                // Advance index until colon is found (skipping any intervening whitespace).
                while index < scalars.endIndex, scalars[index] != ":", CharacterSet.whitespacesAndNewlines.contains(scalars[index]) {
                    index += 1
                }
                index += 1 // Skip the colon.
                guard index < scalars.endIndex
                    else { return .failure(.object(.malformed(index: startIndex))) }
                // Parse corresponding value recursively.
                let value = parse(scalars: scalars, index: &index)
                switch (key, value) {
                case let (.success(key), .success(value)):
                    elements[key] = value
                // Propagate any error from key or value parsing.
                case let (.failure(error), _),
                     let (_, .failure(error)):
                    return .failure(error)
                }
                // Handle comma separation or end of object.
                while index < scalars.endIndex, scalars[index] != "," {
                    switch scalars[index] {
                    case _ where CharacterSet.whitespacesAndNewlines.contains(scalars[index]):
                        index += 1
                    case "}":
                        index += 1
                        return .success(elements)
                    default:
                        return .failure(.object(.malformed(index: index)))
                    }
                }
                index += 1 // Skip comma.
            default:
                return .failure(.object(.malformed(index: index)))
            }
        }
        guard index < scalars.endIndex
            else { return .failure(.object(.malformed(index: startIndex))) }
        index += 1 // Skip closing '}'.
        return .success(elements)
    }
    
    // Parses a JSON array, collecting elements recursively.
    internal static func parseArray(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<[JSON], Error> {
        let startIndex = index
        // Ensure array starts with '['.
        guard index < scalars.endIndex,
            scalars[index] == "["
            else { return .failure(.array(.malformed(index: startIndex))) }
        var elements: [JSON] = []
        index += 1
        while index < scalars.endIndex, scalars[index] != "]" {
            let scalar = scalars[index]
            switch scalar {
            // A comma at this point indicates a malformed array.
            case ",":
                return .failure(.array(.malformed(index: startIndex)))
            case _ where CharacterSet.whitespacesAndNewlines.contains(scalar):
                index += 1
            default:
                // Parse the next array element.
                switch parse(scalars: scalars, index: &index) {
                case .failure(let error):
                    return .failure(error)
                case .success(let value):
                    elements.append(value)
                }
                // After an element, expect a comma or the end of the array.
                while index < scalars.endIndex, scalars[index] != "," {
                    let scalar = scalars[index]
                    switch scalar {
                    case _ where CharacterSet.whitespacesAndNewlines.contains(scalar):
                        index += 1
                    case "]":
                        index += 1
                        return .success(elements)
                    default:
                        return .failure(.array(.malformed(index: startIndex)))
                    }
                }
                index += 1 // Skip comma.
            }
        }
        guard index < scalars.endIndex
            else { return .failure(.array(.malformed(index: startIndex))) }
        index += 1 // Skip closing ']'.
        return .success(elements)
    }
    
    // Parses the literal 'null'.
    internal static func parseNull(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<JSON, Error.Null> {
        guard index < scalars.endIndex
            else { return .failure(.malformed(index: index)) }
        let literal = "null"
        // Check that the next characters match "null".
        if scalars.dropFirst(index).prefix(literal.count) == ArraySlice(literal.unicodeScalars) {
            index += literal.count
            return .success(.null)
        } else {
            return .failure(.malformed(index: index))
        }
    }
    
    // Parses boolean literals ('true' or 'false').
    internal static func parseBool(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<Bool, Error.Bool> {
        guard index < scalars.endIndex
            else { return .failure(.malformed(index: index)) }
        switch scalars[index] {
        // Match "true" literal.
        case "t" where scalars.dropFirst(index).prefix(true.description.count) == ArraySlice(true.description.unicodeScalars):
            index += true.description.count
            return .success(true)
        // Match "false" literal.
        case "f" where scalars.dropFirst(index).prefix(false.description.count) == ArraySlice(false.description.unicodeScalars):
            index += false.description.count
            return .success(false)
        default:
            return .failure(.malformed(index: index))
        }
    }
    
    // Parses a JSON string, handling escape sequences and Unicode escapes.
    internal static func parseString(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<String, Error.String> {
        guard index < scalars.endIndex
            else { return .failure(.unterminated(index: index)) }
        var string = [UnicodeScalar]()
        let startIndex = index
        // Must begin with a double quote.
        guard scalars[index] == "\""
            else { return .failure(.unterminated(index: startIndex)) }
        index += 1
        // Process characters until closing quote.
        while index < scalars.endIndex, scalars[index] != "\"" {
            let scalar = scalars[index]
            switch scalar {
            case "\\":
                // Ensure escape sequence has a following character.
                guard index + 1 < scalars.endIndex else { return .failure(.escapeSequence(index: startIndex)) }
                index += 1
                let scalar = scalars[index]
                // Handle common escape characters.
                switch scalar {
                case "/", "\\", "\"":
                    string.append(scalar)
                case "n":
                    string.append("\n")
                case "r":
                    string.append("\r")
                case "t":
                    string.append("\t")
                case "f":
                    string.append(.init(12))
                case "b":
                    string.append(.init(8))
                case "u":
                    // Parse 4-digit Unicode escape.
                    guard index + 4 < scalars.endIndex,
                        let unicode = UInt32(
                            String(
                                scalars[(index + 1)...(index + 4)]
                                    .map(Character.init)
                            ).uppercased(),
                            radix: 16
                        ).flatMap(UnicodeScalar.init)
                        else { return .failure(.malformedUnicode(index: startIndex)) }
                    string.append(unicode)
                    index += 4
                default:
                    return .failure(.escapeCharacter(index: index))
                }
            default:
                string.append(scalar)
            }
            index += 1
        }
        // Ensure closing quote exists.
        guard index < scalars.endIndex, scalars[index] == "\""
            else { return .failure(.unterminated(index: startIndex)) }
        index += 1
        return .success(String(string.map(Character.init)))
    }
    
    // Parses a JSON number into its string representation.
    internal static func parseNumber(
        scalars: Array<UnicodeScalar>,
        index: inout Array<UnicodeScalar>.Index
    ) -> Result<String, Error.Number> {
        guard index < scalars.endIndex else {
            return .failure(.malformed(index: index))
        }
        // Helper to convert an array of scalars to a String.
        let transform: ([UnicodeScalar]) -> Result<String, Error.Number> = { scalars in
            .success(
                String(
                    scalars.map(Character.init)
                )
            )
        }
        var number: [UnicodeScalar] = []
        let startIndex = index
        // Handle optional negative sign.
        switch scalars[index] {
        case "-":
            number.append(scalars[index])
            index += 1
        default:
            break
        }
        
        // Accumulate digits for the integer part.
        var significant: [UnicodeScalar] = []
        while index < scalars.endIndex, isNumeric(scalars[index]) {
            significant.append(scalars[index])
            index += 1
        }
        
        // Disallow numbers with a leading zero followed by other digits.
        switch (significant.first, significant.dropFirst().first) {
        case ("0"?, _?):
            return .failure(.numberBeginningWithZero(index: startIndex))
        default:
            break
        }
        
        number.append(contentsOf: significant)
        
        guard index < scalars.endIndex
            else { return transform(number) }
        
        // Process fractional part if present.
        switch scalars[index] {
        case ".":
            number.append(scalars[index])
            index += 1
            guard index < scalars.endIndex, isNumeric(scalars[index])
                else { return .failure(.malformed(index: index)) }
            while index < scalars.endIndex, isNumeric(scalars[index]) {
                number.append(scalars[index])
                index += 1
            }
            guard index < scalars.endIndex
                else { return transform(number) }
        default:
            break
        }
        
        // Process exponent part if present.
        switch scalars[index] {
        case "e", "E":
            number.append(scalars[index])
            index += 1
            guard index < scalars.endIndex
                else { return .failure(.malformed(index: startIndex)) }
            switch scalars[index] {
            case "-", "+":
                number.append(scalars[index])
                index += 1
                guard index < scalars.endIndex, isNumeric(scalars[index])
                    else { return .failure(.malformed(index: startIndex)) }
            case _ where isNumeric(scalars[index]):
                break
            default:
                return .failure(.malformed(index: startIndex))
            }
            while index < scalars.endIndex, isNumeric(scalars[index]) {
                number.append(scalars[index])
                index += 1
            }
        default:
            break
        }
        
        return transform(number)
    }
}

// Utility to determine if a UnicodeScalar represents a valid JSON digit.
internal extension JSONParser {
    @inlinable
    static func isNumeric(_ scalar: UnicodeScalar) -> Bool {
        switch scalar {
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return true
        default:
            return false
        }
    }
}
