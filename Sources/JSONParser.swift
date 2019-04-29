//
//  JSONParser.swift
//  MonadicJSON macOS
//
//  Created by Charlotte Tortorella on 18/4/19.
//

import Foundation

public struct JSONParser {
    public enum Error: Swift.Error, Equatable {
        public enum String: Swift.Error, Equatable {
            case escapeSequence(index: Int)
            case escapeCharacter(index: Int)
            case malformedUnicode(index: Int)
            case unterminated(index: Int)
        }
        public enum Number: Swift.Error, Equatable {
            case malformed(index: Int)
            case numberBeginningWithZero(index: Int)
        }
        public enum Bool: Swift.Error, Equatable {
            case malformed(index: Int)
        }
        public enum Null: Swift.Error, Equatable {
            case malformed(index: Int)
        }
        public enum Array: Swift.Error, Equatable {
            case malformed(index: Int)
        }
        public enum Dictionary: Swift.Error, Equatable {
            case malformed(index: Int)
        }
        case empty
        case invalidCharacter(UnicodeScalar, index: Int)
        case string(String)
        case number(Number)
        case bool(Bool)
        case null(Null)
        case array(Array)
        case dictionary(Dictionary)
    }
    
    public static func parse(data: Data) -> Result<JSON, Error> {
        guard let string = String(data: data, encoding: .utf8) else { return .failure(.empty) }
        var index = 0
        return parse(scalars: Array(string.unicodeScalars), index: &index)
    }
    
    internal static func parse(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<JSON, Error> {
        while index < scalars.endIndex {
            let scalar = scalars[index]
            guard !CharacterSet.whitespacesAndNewlines.contains(scalar) else {
                index += 1
                continue
            }
            switch scalar {
            case "{":
                return parseDictionary(scalars: scalars, index: &index)
                    .map(JSON.dictionary)
            case "[":
                return parseArray(scalars: scalars, index: &index)
                    .map(JSON.array)
            case "\"":
                return parseString(scalars: scalars, index: &index)
                    .map(JSON.string)
                    .mapError(Error.string)
            case "-", "0"..."9":
                return parseNumber(scalars: scalars, index: &index)
                    .map(JSON.number)
                    .mapError(Error.number)
            case "n":
                return parseNull(scalars: scalars, index: &index)
                    .mapError(Error.null)
            case "t", "f":
                return parseBool(scalars: scalars, index: &index)
                    .map(JSON.bool)
                    .mapError(Error.bool)
            default:
                return .failure(.invalidCharacter(scalar, index: index))
            }
        }
        return .failure(.empty)
    }
    
    internal static func parseDictionary(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<[String: JSON], Error> {
        let startIndex = index
        guard index < scalars.endIndex,
            scalars[index] == "{"
            else { return .failure(.dictionary(.malformed(index: index))) }
        var elements: [String: JSON] = [:]
        index += 1
        while index < scalars.endIndex, scalars[index] != "}" {
            switch scalars[index] {
            case _ where CharacterSet.whitespacesAndNewlines.contains(scalars[index]):
                index += 1
            case "\"":
                let key = parseString(scalars: scalars, index: &index).mapError(Error.string)
                while index < scalars.endIndex, scalars[index] != ":", CharacterSet.whitespacesAndNewlines.contains(scalars[index]) {
                    index += 1
                }
                index += 1
                guard index < scalars.endIndex
                    else { return .failure(.dictionary(.malformed(index: startIndex))) }
                let value = parse(scalars: scalars, index: &index)
                switch (key, value) {
                case let (.success(key), .success(value)):
                    elements[key] = value
                case let (.failure(error), _),
                     let (_, .failure(error)):
                    return .failure(error)
                }
                while index < scalars.endIndex, scalars[index] != "," {
                    switch scalars[index] {
                    case _ where CharacterSet.whitespacesAndNewlines.contains(scalars[index]):
                        index += 1
                    case "}":
                        index += 1
                        return .success(elements)
                    default:
                        return .failure(.dictionary(.malformed(index: index)))
                    }
                }
                index += 1
            default:
                return .failure(.dictionary(.malformed(index: index)))
            }
        }
        guard index < scalars.endIndex
            else { return .failure(.dictionary(.malformed(index: startIndex))) }
        index += 1
        return .success(elements)
    }
    
    internal static func parseArray(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<[JSON], Error> {
        let startIndex = index
        guard index < scalars.endIndex,
            scalars[index] == "["
            else { return .failure(.array(.malformed(index: startIndex))) }
        var elements: [JSON] = []
        index += 1
        while index < scalars.endIndex, scalars[index] != "]" {
            let scalar = scalars[index]
            switch scalar {
            case ",":
                return .failure(.array(.malformed(index: startIndex)))
            case _ where CharacterSet.whitespacesAndNewlines.contains(scalar):
                index += 1
            default:
                switch parse(scalars: scalars, index: &index) {
                case .failure(let error):
                    return .failure(error)
                case .success(let value):
                    elements.append(value)
                }
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
                index += 1
            }
        }
        guard index < scalars.endIndex
            else { return .failure(.array(.malformed(index: startIndex))) }
        index += 1
        return .success(elements)
    }
    
    internal static func parseNull(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<JSON, Error.Null> {
        guard index < scalars.endIndex
            else { return .failure(.malformed(index: index)) }
        let literal = "null"
        if scalars.dropFirst(index).prefix(literal.count) == ArraySlice(literal.unicodeScalars) {
            index += literal.count
            return .success(.null)
        } else {
            return .failure(.malformed(index: index))
        }
    }
    
    internal static func parseBool(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<Bool, Error.Bool> {
        guard index < scalars.endIndex
            else { return .failure(.malformed(index: index)) }
        switch scalars[index] {
        case "t" where scalars.dropFirst(index).prefix(true.description.count) == ArraySlice(true.description.unicodeScalars):
            index += true.description.count
            return .success(true)
        case "f" where scalars.dropFirst(index).prefix(false.description.count) == ArraySlice(false.description.unicodeScalars):
            index += false.description.count
            return .success(false)
        default:
            return .failure(.malformed(index: index))
        }
    }
    
    internal static func parseString(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<String, Error.String> {
        guard index < scalars.endIndex
            else { return .failure(.unterminated(index: index)) }
        var string = [UnicodeScalar]()
        let startIndex = index
        guard scalars[index] == "\""
            else { return .failure(.unterminated(index: startIndex)) }
        index += 1
        while index < scalars.endIndex, scalars[index] != "\"" {
            let scalar = scalars[index]
            switch scalar {
            case "\\":
                guard index + 1 < scalars.endIndex else { return .failure(.escapeSequence(index: startIndex)) }
                index += 1
                let scalar = scalars[index]
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
                    guard index + 4 < scalars.endIndex,
                        let unicode = UInt32(String(scalars[(index + 1)...(index + 4)].map(Character.init)).uppercased(), radix: 16).flatMap(UnicodeScalar.init)
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
        guard index < scalars.endIndex, scalars[index] == "\""
            else { return .failure(.unterminated(index: startIndex)) }
        index += 1
        return .success(String(string.map(Character.init)))
    }
    
    internal static func parseNumber(scalars: Array<UnicodeScalar>, index: inout Array<UnicodeScalar>.Index) -> Result<String, Error.Number> {
        guard index < scalars.endIndex
            else { return .failure(.malformed(index: index)) }
        let transform: ([UnicodeScalar]) -> Result<String, Error.Number> = { .success(String($0.map(Character.init))) }
        var number: [UnicodeScalar] = []
        let startIndex = index
        switch scalars[index] {
        case "-":
            number.append(scalars[index])
            index += 1
        default:
            break
        }
        
        // Append all digits occurring until a non-digit is found.
        var significant: [UnicodeScalar] = []
        while index < scalars.endIndex, isNumeric(scalars[index]) {
            significant.append(scalars[index])
            index += 1
        }
        
        switch (significant.first, significant.dropFirst().first) {
        case ("0"?, _?):
            return .failure(.numberBeginningWithZero(index: startIndex))
        default:
            break
        }
        
        number.append(contentsOf: significant)
        
        guard index < scalars.endIndex
            else { return transform(number) }
        
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
