import Foundation

extension JSONParser {
    // Begins JSON parsing from an InputStream by initializing state.
    public static func parse(stream: InputStream) -> Result<JSON, Error> {
        var index = 0
        var scalar = stream.getNextScalar()
        return parseStream(stream: stream, scalar: &scalar, index: &index)
    }

    // Recursively parses JSON tokens from the stream, skipping whitespace.
    internal static func parseStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<JSON, Error>  {
        while scalar != .eof {
            // Ignore whitespace characters.
            guard !CharacterSet.whitespacesAndNewlines.contains(scalar) else {
                scalar = stream.getNextScalar()
                index += 1
                continue
            }
            // Dispatch based on the current token.
            return switch scalar {
            case "{":
                parseDictionaryStream(stream: stream, scalar: &scalar, index: &index)
                    .map(JSON.object)
            case "[":
                parseArrayStream(stream: stream, scalar: &scalar, index: &index)
                    .map(JSON.array)
            case "\"":
                parseStringStream(stream: stream, scalar: &scalar, index: &index)
                    .map(JSON.string)
                    .mapError(Error.string)
            case "-", "0"..."9":
                parseNumberStream(stream: stream, scalar: &scalar, index: &index)
                    .map(JSON.number)
                    .mapError(Error.number)
            case "n":
                parseNullStream(stream: stream, scalar: &scalar, index: &index)
                    .mapError(Error.null)
            case "t", "f":
                parseBoolStream(stream: stream, scalar: &scalar, index: &index)
                    .map(JSON.bool)
                    .mapError(Error.bool)
            default:
                .failure(.invalidCharacter(scalar, index: index))
            }
        }
        return .failure(.empty)
    }

    // Parses a JSON object from the stream.
    internal static func parseDictionaryStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<[String: JSON], Error> {
        let startIndex = index
        // Ensure the object starts with '{'.
        guard scalar != .eof,
              scalar == "{"
        else { return .failure(.object(.malformed(index: index))) }
        var elements: [String: JSON] = [:]
        scalar = stream.getNextScalar()
        index += 1
        while scalar != .eof, scalar != "}" {
            switch scalar {
            // Skip any whitespace between tokens.
            case _ where CharacterSet.whitespacesAndNewlines.contains(scalar):
                scalar = stream.getNextScalar()
                index += 1
            case "\"":
                // Parse a key and then move to the colon separator.
                let key = parseStringStream(stream: stream, scalar: &scalar, index: &index).mapError(Error.string)
                while scalar != .eof, scalar != ":", CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    scalar = stream.getNextScalar()
                    index += 1
                }
                // Consume the colon.
                scalar = stream.getNextScalar()
                index += 1
                guard scalar != .eof
                else { return .failure(.object(.malformed(index: startIndex))) }
                // Parse the associated value.
                let value = parseStream(stream: stream, scalar: &scalar, index: &index)
                switch (key, value) {
                case let (.success(key), .success(value)):
                    elements[key] = value
                case let (.failure(error), _),
                     let (_, .failure(error)):
                    return .failure(error)
                }
                // Expect a comma or the closing brace.
                while scalar != .eof, scalar != "," {
                    switch scalar {
                    case _ where CharacterSet.whitespacesAndNewlines.contains(scalar):
                        scalar = stream.getNextScalar()
                        index += 1
                    case "}":
                        scalar = stream.getNextScalar()
                        index += 1
                        return .success(elements)
                    default:
                        return .failure(.object(.malformed(index: index)))
                    }
                }
                // Consume the comma.
                scalar = stream.getNextScalar()
                index += 1
            default:
                return .failure(.object(.malformed(index: index)))
            }
        }
        guard scalar != .eof
        else { return .failure(.object(.malformed(index: startIndex))) }
        // Consume the closing '}'.
        scalar = stream.getNextScalar()
        index += 1
        return .success(elements)
    }

    // Parses a JSON array from the stream.
    internal static func parseArrayStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<[JSON], Error> {
        let startIndex = index
        // Ensure the array starts with '['.
        guard scalar != .eof,
              scalar == "["
        else { return .failure(.array(.malformed(index: startIndex))) }
        var elements: [JSON] = []
        scalar = stream.getNextScalar()
        index += 1
        while scalar != .eof, scalar != "]" {
            switch scalar {
            // A leading comma is invalid.
            case ",":
                return .failure(.array(.malformed(index: startIndex)))
            case _ where CharacterSet.whitespacesAndNewlines.contains(scalar):
                scalar = stream.getNextScalar()
                index += 1
            default:
                // Parse the next element.
                switch parseStream(stream: stream, scalar: &scalar, index: &index) {
                case .failure(let error):
                    return .failure(error)
                case .success(let value):
                    elements.append(value)
                }
                // After an element, expect a comma or the closing bracket.
                while scalar != .eof, scalar != "," {
                    switch scalar {
                    case _ where CharacterSet.whitespacesAndNewlines.contains(scalar):
                        scalar = stream.getNextScalar()
                        index += 1
                    case "]":
                        scalar = stream.getNextScalar()
                        index += 1
                        return .success(elements)
                    default:
                        return .failure(.array(.malformed(index: startIndex)))
                    }
                }
                // Consume the comma.
                scalar = stream.getNextScalar()
                index += 1
            }
        }
        guard scalar != .eof
        else { return .failure(.array(.malformed(index: startIndex))) }
        // Consume the closing ']'.
        scalar = stream.getNextScalar()
        index += 1
        return .success(elements)
    }

    // Parses the 'null' literal from the stream.
    internal static func parseNullStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<JSON, Error.Null> {
        guard scalar != .eof
        else { return .failure(.malformed(index: index)) }
        let literal = "null"
        // Attempt to read the next 3 scalars to complete the literal.
        let scalars = [scalar] + stream.getNextScalars(3)
        if scalars == Array(literal.unicodeScalars) {
            index += (literal.count - 1)
            return .success(.null)
        } else {
            return .failure(.malformed(index: index))
        }
    }

    // Parses a boolean literal ('true' or 'false') from the stream.
    internal static func parseBoolStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<Bool, Error.Bool> {
        guard scalar != .eof
        else { return .failure(.malformed(index: index)) }
        switch scalar {
        case "t":
            let literal = "true"
            let scalars = [scalar] + stream.getNextScalars(literal.count - 1)
            if scalars == Array(literal.unicodeScalars) {
                index += literal.count
                scalar = stream.getNextScalar()
                return .success(true)
            } else {
                return .failure(.malformed(index: index))
            }
        case "f":
            let literal = "false"
            let scalars = [scalar] + stream.getNextScalars(literal.count - 1)
            if scalars == Array(literal.unicodeScalars) {
                scalar = stream.getNextScalar()
                index += literal.count
                return .success(false)
            } else {
                return .failure(.malformed(index: index))
            }
        default:
            return .failure(.malformed(index: index))
        }
    }

    // Parses a JSON string from the stream, handling escape sequences.
    internal static func parseStringStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<String, Error.String> {
        guard scalar != .eof else {
            return .failure(.unterminated(index: index))
        }
        var string = [UnicodeScalar]()
        let startIndex = index
        // Ensure string starts with a double quote.
        guard scalar == "\"" else {
            return .failure(.unterminated(index: startIndex))
        }
        scalar = stream.getNextScalar()
        index += 1

        while scalar != .eof, scalar != "\"" {
            switch scalar {
            case "\\":
                // Process escape sequence.
                scalar = stream.getNextScalar()
                guard scalar != .eof else {
                    return .failure(.escapeSequence(index: startIndex))
                }
                index += 1
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
                    // Read the next 4 scalars for a Unicode escape.
                    let unicodeScalars = stream.getNextScalars(4)
                    guard unicodeScalars.count == 4,
                          let unicode = UInt32(
                            String(
                                unicodeScalars
                                    .map(Character.init)
                            ).uppercased(),
                            radix: 16
                          ).flatMap(UnicodeScalar.init)
                    else {
                        return .failure(.malformedUnicode(index: startIndex))
                    }
                    string.append(unicode)
                    index += 4
                default:
                    return .failure(.escapeCharacter(index: index))
                }
            default:
                string.append(scalar)
            }
            scalar = stream.getNextScalar()
            index += 1
        }
        // Verify the string is properly terminated.
        guard scalar == "\"" else {
            return .failure(.unterminated(index: startIndex))
        }
        scalar = stream.getNextScalar()
        index += 1
        return .success(String(string.map(Character.init)))
    }

    // Parses a JSON number from the stream into its string representation.
    internal static func parseNumberStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<String, Error.Number> {
        guard scalar != .eof else { return .failure(.malformed(index: index)) }
        let transform: ([UnicodeScalar]) -> Result<String, Error.Number> = { .success(String($0.map(Character.init))) }
        var number: [UnicodeScalar] = []
        let startIndex = index
        // Process optional negative sign.
        switch scalar {
        case "-":
            number.append(scalar)
            scalar = stream.getNextScalar()
            index += 1
        default:
            break
        }

        // Accumulate the integer digits.
        var significant: [UnicodeScalar] = []
        while scalar != .eof, isNumeric(scalar) {
            significant.append(scalar)
            scalar = stream.getNextScalar()
            index += 1
        }

        // Reject numbers with invalid leading zero.
        switch (significant.first, significant.dropFirst().first) {
        case ("0"?, _?):
            return .failure(.numberBeginningWithZero(index: startIndex))
        default:
            break
        }

        number.append(contentsOf: significant)

        guard scalar != .eof else { return transform(number) }

        // Process the fractional part if present.
        switch scalar {
        case ".":
            number.append(scalar)
            scalar = stream.getNextScalar()
            index += 1
            guard scalar != .eof, isNumeric(scalar) else {
                return .failure(.malformed(index: index))
            }
            while scalar != .eof, isNumeric(scalar) {
                number.append(scalar)
                scalar = stream.getNextScalar()
                index += 1
            }
            guard scalar != .eof else {
                return transform(number)
            }
        default:
            break
        }

        // Process the exponent if present.
        switch scalar {
        case "e", "E":
            number.append(scalar)
            scalar = stream.getNextScalar()
            index += 1
            guard scalar != .eof else {
                return .failure(.malformed(index: startIndex))
            }
            switch scalar {
            case "-", "+":
                number.append(scalar)
                scalar = stream.getNextScalar()
                index += 1
                guard scalar != .eof, isNumeric(scalar) else {
                    return .failure(.malformed(index: startIndex))
                }
            case _ where isNumeric(scalar):
                break
            default:
                return .failure(.malformed(index: startIndex))
            }
            while scalar != .eof, isNumeric(scalar) {
                number.append(scalar)
                scalar = stream.getNextScalar()
                index += 1
            }
        default:
            break
        }
        return transform(number)
    }
}

extension InputStream {
    // Reads the next UnicodeScalar from the stream, handling UTF-8 multibyte sequences.
    func getNextScalar() -> UnicodeScalar {
        if hasBytesAvailable {
            // Allocate enough data for the maximum UTF-8 scalar (4 bytes).
            var data = Data(count: 4)
            let readBytes = data.withUnsafeMutableBytes { (pointer) -> Int in
                guard let baseAddress = pointer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                // Read the first byte to determine the length.
                var result = read(baseAddress, maxLength: 1)
                let bytesForUnicodeCodepoint = numberOfBytesForUnicodeCodepoint(baseAddress[0])
                if bytesForUnicodeCodepoint == 0 {
                    return 0
                }
                if bytesForUnicodeCodepoint == 1 {
                    return result
                }
                // Read remaining bytes for the complete codepoint.
                result += read(baseAddress.advanced(by: 1), maxLength: bytesForUnicodeCodepoint - 1)
                return result
            }
            if readBytes == 0 {
                return .eof
            }
            // Attempt to decode the read bytes as UTF-8.
            guard let string = String(data: data, encoding: .utf8) else {
                return .eof
            }
            return string.unicodeScalars.first ?? .eof
        }
        return .eof
    }

    // Determines how many bytes are expected for the current UTF-8 codepoint.
    private func numberOfBytesForUnicodeCodepoint(_ byte: UInt8) -> Int {
        if byte & 0b1000_0000 == 0b0000_0000 {
            return 1
        } else if byte & 0b1110_0000 == 0b1100_0000 {
            return 2
        } else if byte & 0b1111_0000 == 0b1110_0000 {
            return 3
        } else if byte & 0b1111_1000 == 0b1111_0000 {
            return 4
        }
        return 0
    }

    // Reads the next 'count' UnicodeScalars from the stream.
    func getNextScalars(_ count: Int) -> [UnicodeScalar] {
        var scalars: [UnicodeScalar] = []
        for _ in 0..<count {
            scalars.append(getNextScalar())
        }
        return scalars
    }
}

extension UnicodeScalar {
    // Represents end-of-file for stream parsing.
    internal static var eof: UnicodeScalar { "\0" }
}
