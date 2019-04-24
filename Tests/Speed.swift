//
//  Speed.swift
//  MonadicJSON macOS
//
//  Created by Charlotte Tortorella on 24/4/19.
//

import XCTest
import SwiftCheck
@testable import MonadicJSON

fileprivate let measuringSize = 1e2
fileprivate let measuringSeed = CheckerArguments(replay: (StdGen(1, 1), 100))

class SpeedTests: XCTestCase {
    typealias TypeOne = [Int]
    typealias TypeTwo = [Decimal]
    typealias TypeThree = [Bool]
    typealias TypeFour = [String]
    typealias TypeFive = [String: TypeOne]
    typealias TypeSix = [String: TypeTwo]
    typealias TypeSeven = [String: TypeThree]
    typealias TypeEight = [String: TypeFour]
    typealias TypeNine = [String: TypeFive]
    typealias TypeTen = [String: TypeSix]
    
    func speedTester<T: Arbitrary & Codable & Equatable>(_ type: T.Type, size: Int, decoder: TopLevelDecoder, closure: @escaping (() -> Void) -> Void) {
        property("Test \(decoder.description) Decoder Speed", arguments: measuringSeed) <- forAllNoShrink(T.arbitrary.resize(size)) { value in
            let json = try! encoder.encode(DecoderTest(value: value))
            closure({
                _ = try! decoder.decode(DecoderTest<T>.self, from: json)
            })
            return true
        }.once
    }
    
    func speedTestFoundation<T: Arbitrary & Codable & Equatable>(_ type: T.Type, size: Double = measuringSize, closure: @escaping (() -> Void) -> Void) {
        speedTester(T.self, size: Int(size), decoder: JSONDecoder(), closure: closure)
    }
    
    func speedTestMonadic<T: Arbitrary & Codable & Equatable>(_ type: T.Type, size: Double = measuringSize, closure: @escaping (() -> Void) -> Void) {
        speedTester(T.self, size: Int(size), decoder: MonadicJSONDecoder(), closure: closure)
    }
    
    func testFoundationSpeedOne() {
        speedTestFoundation(TypeOne.self, closure: { self.measure($0) })
    }
    
    func testMonadicSpeedOne() {
        speedTestMonadic(TypeOne.self, closure: { self.measure($0) })
    }
    
    func testFoundationSpeedTwo() {
        speedTestFoundation(TypeTwo.self, closure: { self.measure($0) })
    }
    
    func testMonadicSpeedTwo() {
        speedTestMonadic(TypeTwo.self, closure: { self.measure($0) })
    }
    
    func testFoundationSpeedThree() {
        speedTestFoundation(TypeThree.self, closure: { self.measure($0) })
    }
    
    func testMonadicSpeedThree() {
        speedTestMonadic(TypeThree.self, closure: { self.measure($0) })
    }
    
    func testFoundationSpeedFour() {
        speedTestFoundation(TypeFour.self, closure: { self.measure($0) })
    }
    
    func testMonadicSpeedFour() {
        speedTestMonadic(TypeFour.self, closure: { self.measure($0) })
    }
    
    func testFoundationSpeedFive() {
        speedTestFoundation(TypeFive.self, closure: { self.measure($0) })
    }
    
    func testMonadicSpeedFive() {
        speedTestMonadic(TypeFive.self, closure: { self.measure($0) })
    }
    
    func testFoundationSpeedSix() {
        speedTestFoundation(TypeSix.self, closure: { self.measure($0) })
    }
    
    func testMonadicSpeedSix() {
        speedTestMonadic(TypeSix.self, closure: { self.measure($0) })
    }
    
    func testFoundationSpeedSeven() {
        speedTestFoundation(TypeSeven.self, closure: { self.measure($0) })
    }
    
    func testMonadicSpeedSeven() {
        speedTestMonadic(TypeSeven.self, closure: { self.measure($0) })
    }
    
    func testFoundationSpeedEight() {
        speedTestFoundation(TypeEight.self, closure: { self.measure($0) })
    }
    
    func testMonadicSpeedEight() {
        speedTestMonadic(TypeEight.self, closure: { self.measure($0) })
    }
    
    func testFoundationSpeedNine() {
        speedTestFoundation(TypeNine.self, closure: { self.measure($0) })
    }
    
    func testMonadicSpeedNine() {
        speedTestMonadic(TypeNine.self, closure: { self.measure($0) })
    }
    
    func testFoundationSpeedTen() {
        speedTestFoundation(TypeTen.self, closure: { self.measure($0) })
    }
    
    func testMonadicSpeedTen() {
        speedTestMonadic(TypeTen.self, closure: { self.measure($0) })
    }
}
