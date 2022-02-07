//
//  Types.swift
//  MonadicJSON
//
//  Created by Charlotte Tortorella on 23/4/19.
//

import Foundation
import SwiftCheck
@testable import MonadicJSON

typealias CodableArbitrary = Codable & Arbitrary & Equatable

protocol Integer: Codable, Arbitrary, BinaryInteger {
    static var max: Self { get }
}

enum DecodingType: Arbitrary, CaseIterable {
    case array
    case nestedArray
    case object
    case nestedObject
    
    static var arbitrary: Gen<DecodingType> {
        return .fromElements(of: allCases)
    }
}

struct DecoderTest<T: CodableArbitrary>: Equatable, Codable, Arbitrary {
    let value: T
    
    static var arbitrary: Gen<DecoderTest<T>> {
        return T.arbitrary.map(DecoderTest.init(value:))
    }
}
