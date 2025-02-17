import XCTest
import SwiftCheck
@testable import MonadicJSON

fileprivate let measuringSize = 5e2
fileprivate let measuringSeed = CheckerArguments(replay: (StdGen(1, 1), 100))

class SpeedTests: XCTestCase {
    func testArrays() {
        speedTestMonadic(arrays, closure: { self.measure($0) })
    }
    
    func testDictionaries() {
        speedTestMonadic(dictionaries, closure: { self.measure($0) })
    }

    func testArraysStream() {
        speedTestMonadicStream(arrays, closure: { self.measure($0) })
    }

    func testDictionariesStream() {
        speedTestMonadicStream(dictionaries, closure: { self.measure($0) })
    }
}

extension SpeedTests {
    func speedTester(_ gen: Gen<String>, size: Int, parser: @escaping (String) -> Void, closure: @escaping (() -> Void) -> Void) {
        property("Test parser speed", arguments: measuringSeed) <- forAllNoShrink(gen.resize(size)) { value in
            closure({
                parser(value)
            })
            return true
        }.once
    }
    
    func speedTestMonadic(
        _ gen: Gen<String>,
        size: Double = measuringSize,
        closure: @escaping (() -> Void) -> Void
    ) {
        speedTester(
            gen,
            size: Int(size),
            parser: { _ = JSONParser.parse($0) },
            closure: closure
        )
    }

    func speedTestMonadicStream(
        _ gen: Gen<String>,
        size: Double = measuringSize,
        closure: @escaping (() -> Void) -> Void
    ) {
        speedTester(
            gen,
            size: Int(size),
            parser: { _ = JSONParser.parseStream($0) },
            closure: closure
        )
    }
}
