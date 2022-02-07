//
//  JSONParserStream.swift
//  MonadicJSON macOS
//
//  Created by Charlotte Tortorella on 18/4/19.
//
import Foundation

extension JSONParser {

    public static func parse(stream: InputStream) -> Result<JSON, Error> {
        var index = 0
        var scalar = stream.getNextScalar()
        return parseStream(stream: stream, scalar: &scalar, index: &index)
    }

    internal static func parseStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<JSON, Error>  {
        while scalar != .eof {
            guard !CharacterSet.whitespacesAndNewlines.contains(scalar) else {
                scalar = stream.getNextScalar()
                index += 1
                continue
            }
            switch scalar {
            case "{":
                return parseDictionaryStream(stream: stream, scalar: &scalar, index: &index)
                    .map(JSON.object)
            case "[":
                return parseArrayStream(stream: stream, scalar: &scalar, index: &index)
                    .map(JSON.array)
            case "\"":
                return parseStringStream(stream: stream, scalar: &scalar, index: &index)
                    .map(JSON.string)
                    .mapError(Error.string)
            case "-", "0"..."9":
                return parseNumberStream(stream: stream, scalar: &scalar, index: &index)
                    .map(JSON.number)
                    .mapError(Error.number)
            case "n":
                return parseNullStream(stream: stream, scalar: &scalar, index: &index)
                    .mapError(Error.null)
            case "t", "f":
                return parseBoolStream(stream: stream, scalar: &scalar, index: &index)
                    .map(JSON.bool)
                    .mapError(Error.bool)
            default:
                return .failure(.invalidCharacter(scalar, index: index))
            }
        }
        return .failure(.empty)
    }

    internal static func parseDictionaryStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<[String: JSON], Error> {
        let startIndex = index
        guard scalar != .eof,
            scalar == "{"
            else { return .failure(.object(.malformed(index: index))) }
        var elements: [String: JSON] = [:]
        scalar = stream.getNextScalar()
        index += 1
        while scalar != .eof, scalar != "}" {
            switch scalar {
            case _ where CharacterSet.whitespacesAndNewlines.contains(scalar):
                scalar = stream.getNextScalar()
                index += 1
            case "\"":
                let key = parseStringStream(stream: stream, scalar: &scalar, index: &index).mapError(Error.string)
                while scalar != .eof, scalar != ":", CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    scalar = stream.getNextScalar()
                    index += 1
                }
                scalar = stream.getNextScalar()
                index += 1
                guard scalar != .eof
                    else { return .failure(.object(.malformed(index: startIndex))) }
                let value = parseStream(stream: stream, scalar: &scalar, index: &index)
                switch (key, value) {
                case let (.success(key), .success(value)):
                    elements[key] = value
                case let (.failure(error), _),
                     let (_, .failure(error)):
                    return .failure(error)
                }
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
                scalar = stream.getNextScalar()
                index += 1
            default:
                return .failure(.object(.malformed(index: index)))
            }
        }
        guard scalar != .eof
            else { return .failure(.object(.malformed(index: startIndex))) }
        scalar = stream.getNextScalar()
        index += 1
        return .success(elements)
    }

    internal static func parseArrayStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<[JSON], Error> {
        let startIndex = index
        guard scalar != .eof,
            scalar == "["
            else { return .failure(.array(.malformed(index: startIndex))) }
        var elements: [JSON] = []
        scalar = stream.getNextScalar()
        index += 1
        while scalar != .eof, scalar != "]" {
            switch scalar {
            case ",":
                return .failure(.array(.malformed(index: startIndex)))
            case _ where CharacterSet.whitespacesAndNewlines.contains(scalar):
                scalar = stream.getNextScalar()
                index += 1
            default:
                switch parseStream(stream: stream, scalar: &scalar, index: &index) {
                case .failure(let error):
                    return .failure(error)
                case .success(let value):
                    elements.append(value)
                }
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
                scalar = stream.getNextScalar()
                index += 1
            }
        }
        guard scalar != .eof
            else { return .failure(.array(.malformed(index: startIndex))) }
        scalar = stream.getNextScalar()
        index += 1
        return .success(elements)
    }

    internal static func parseNullStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<JSON, Error.Null> {
        guard scalar != .eof
            else { return .failure(.malformed(index: index)) }
        let literal = "null"
        let scalars = [scalar] + stream.getNextScalars(3)
        if scalars == Array(literal.unicodeScalars) {
            index += (literal.count - 1)
            return .success(.null)
        } else {
            return .failure(.malformed(index: index))
        }
    }

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
            }else {
                return .failure(.malformed(index: index))
            }
        case "f":
            let literal = "false"
            let scalars = [scalar] + stream.getNextScalars(literal.count - 1)
            if scalars == Array(literal.unicodeScalars) {
                scalar = stream.getNextScalar()
                index += literal.count
                return .success(false)
            }else {
                return .failure(.malformed(index: index))
            }
        default:
            return .failure(.malformed(index: index))
        }
    }

    internal static func parseStringStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<String, Error.String> {
        guard scalar != .eof
            else {
                return .failure(.unterminated(index: index))
        }
        var string = [UnicodeScalar]()
        let startIndex = index
        guard scalar == "\""
            else {
                return .failure(.unterminated(index: startIndex))
        }
        scalar = stream.getNextScalar()
        index += 1

        while scalar != .eof, scalar != "\"" {
            switch scalar {
            case "\\":
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
                    let unicodeScalars = stream.getNextScalars(4)
                    guard unicodeScalars.count == 4,
                        let unicode = UInt32(String(unicodeScalars.map(Character.init)).uppercased(), radix: 16).flatMap(UnicodeScalar.init)
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
        guard scalar == "\""
            else {
                return .failure(.unterminated(index: startIndex))
        }
        scalar = stream.getNextScalar()
        index += 1
        return .success(String(string.map(Character.init)))
    }

    internal static func parseNumberStream(stream: InputStream, scalar: inout UnicodeScalar, index: inout Int) -> Result<String, Error.Number> {
        guard scalar != .eof else { return .failure(.malformed(index: index)) }
        let transform: ([UnicodeScalar]) -> Result<String, Error.Number> = { .success(String($0.map(Character.init))) }
        var number: [UnicodeScalar] = []
        let startIndex = index
        switch scalar {
        case "-":
            number.append(scalar)
            scalar = stream.getNextScalar()
            index += 1
        default:
            break
        }

        // Append all digits occurring until a non-digit is found.
        var significant: [UnicodeScalar] = []
        while scalar != .eof, isNumeric(scalar) {
            significant.append(scalar)
            scalar = stream.getNextScalar()
            index += 1
        }

        switch (significant.first, significant.dropFirst().first) {
        case ("0"?, _?):
            return .failure(.numberBeginningWithZero(index: startIndex))
        default:
            break
        }

        number.append(contentsOf: significant)

        guard scalar != .eof
            else { return transform(number) }

        switch scalar {
        case ".":
            number.append(scalar)
            scalar = stream.getNextScalar()
            index += 1
            guard scalar != .eof, isNumeric(scalar)
                else { return .failure(.malformed(index: index)) }
            while scalar != .eof, isNumeric(scalar) {
                number.append(scalar)
                scalar = stream.getNextScalar()
                index += 1
            }
            guard scalar != .eof
                else { return transform(number) }
        default:
            break
        }

        switch scalar {
        case "e", "E":
            number.append(scalar)
            scalar = stream.getNextScalar()
            index += 1
            guard scalar != .eof
                else { return .failure(.malformed(index: startIndex)) }
            switch scalar {
            case "-", "+":
                number.append(scalar)
                scalar = stream.getNextScalar()
                index += 1
                guard scalar != .eof, isNumeric(scalar)
                    else { return .failure(.malformed(index: startIndex)) }
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
    func getNextScalar() -> UnicodeScalar {
        if hasBytesAvailable {
            //With UTF8 a UnicodeScalar can be 4 bytes
            var data = Data(count: 4)
            let readBytes = data.withUnsafeMutableBytes { (pointer) -> Int in
                guard let baseAddress = pointer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                var result = read(baseAddress, maxLength: 1)
                let bytesForUnicodeCodepoint = numberOfBytesForUnicodeCodepoint(baseAddress[0])
                if bytesForUnicodeCodepoint == 0 {
                    return 0
                }
                if bytesForUnicodeCodepoint == 1 {
                    return result
                }
                result += read(baseAddress.advanced(by: 1), maxLength: bytesForUnicodeCodepoint - 1)
                return result
            }
            if readBytes == 0 {
                return .eof
            }
            guard let string = String(data: data, encoding: .utf8) else {
                return .eof
            }
            return string.unicodeScalars.first ?? .eof
        }
        return .eof
    }

    private func numberOfBytesForUnicodeCodepoint(_ byte: UInt8) -> Int {
        if byte & 0b1000_0000 == 0b0000_0000 {
            return 1
        }
        else if byte & 0b1110_0000 == 0b1100_0000 {
            return 2
        }
        else if byte & 0b1111_0000 == 0b1110_0000 {
            return 3
        }
        else if byte & 0b1111_1000 == 0b1111_0000 {
            return 4
        }
        return 0
    }

    func getNextScalars(_ count: Int) -> [UnicodeScalar] {
        var scalars: [UnicodeScalar] = []
        for _ in 0..<count {
            scalars.append(getNextScalar())
        }
        return scalars
    }
}

extension UnicodeScalar {
    internal static var eof: UnicodeScalar { "\0" }
}
