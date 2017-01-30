//
//  OrderedDictionaryTests.swift
//  ale
//
//  Created by Zachary Waldowski on 12/08/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import XCTest

#if SWIFT_PACKAGE
@testable import YAML
#else
@testable import ale
#endif

class OrderedDictionaryTests: XCTestCase {

    typealias TestOrderedDictionary = OrderedDictionary<String, Int>
    var d: TestOrderedDictionary!

    override func setUp() {
        super.setUp()

        d = OrderedDictionary()
        d["0"] = 1
        d["1"] = 2
        d["3"] = 4
        d["2"] = 3
        d["1"] = 7
        d["3"] = nil

        XCTAssertFalse(d.isEmpty)
        XCTAssertEqual(d.count, 3)
    }

    override func tearDown() {
        d = nil

        super.tearDown()
    }

    func testEquivalentDictionary() {
        var d2 = [String: Int]()
        d2["0"] = 1
        d2["1"] = 2
        d2["3"] = 4
        d2["2"] = 3
        d2["1"] = 7
        d2.removeValue(forKey: "3")

        XCTAssertFalse(d2.keys.elementsEqual(["0", "1", "2"]))
        XCTAssertEqual(d2["0"], 1)
        XCTAssertEqual(d2["1"], 7)
        XCTAssertEqual(d2["2"], 3)
    }

    func testOrderPreserved() {
        XCTAssertEqual(d.keys, ["0", "1", "2"])
        XCTAssertEqual(d["0"], 1)
        XCTAssertEqual(d["1"], 7)
        XCTAssertEqual(d["2"], 3)
    }

    func testLiteralSequence() {
        let d3: OrderedDictionary<String, Int> = [
            "3": 900,
            "2": 1000,
            "1": 2000
        ]
        XCTAssertEqual(d3.keys, ["3", "2", "1"])
    }

    func testIndexing() {
        XCTAssertEqual(d.startIndex, 0)
        XCTAssertEqual(d.endIndex, d.count)
        XCTAssert(d.first! == (key: "0", value: 1))
    }

    func testSlicing() {
        XCTAssert(d.elementsEqual([
            (key: "0", value: 1),
            (key: "1", value: 7),
            (key: "2", value: 3)
        ], by: ==))

        XCTAssert(d.prefix(upTo: 2).elementsEqual([
            ("0", 1),
            ("1", 7)
        ], by: ==))
    }

    func testMutableIndexing() {
        d[2] = ("99", 100)
        XCTAssert(d.keys.elementsEqual([ "0", "1", "99" ]))
        XCTAssert(d.values.elementsEqual([ 1, 7, 100 ]))
    }

    func testInsertAt() {
        d.insert((key: "7", value: 64), at: 1)
        XCTAssertEqual(d.keys, ["0", "7", "1", "2"])
    }

    func testRemoveAtIndex() {
        XCTAssert(d.remove(at: 1) == (key: "1", value: 7))
        XCTAssertEqual(d.keys, ["0", "2"])
    }

    func testRemoveNonExistantKey() {
        XCTAssertNil(d.removeValue(forKey: "foo"))
    }

    func testRemoveAll() {
        d.removeAll()
        XCTAssert(d.isEmpty)
        XCTAssertEqual(d.count, 0)
    }

}
