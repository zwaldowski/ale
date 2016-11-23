//
//  OptionTests.swift
//  Commandant
//
//  Created by Justin Spahr-Summers on 2014-10-25.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import XCTest

#if SWIFT_PACKAGE
import Command
#else
@testable import ale
#endif

class OptionTests: XCTestCase {

    private func tryArguments(_ arguments: String...) throws -> TestOptions {
        let parser = ArgumentParser(for: TestOptions.self)
        try parser.parse(arguments: arguments)
        return try TestOptions(parsedFrom: parser)
    }

    func testArgumentsShouldFailRequiredArguments() {
        XCTAssertThrowsError(try tryArguments())
    }

    func testArgumentsShouldFailMissingValues() {
        XCTAssertThrowsError(try tryArguments("required", "--intValue"))
    }

    func testArgumentsShouldSucceedWithNoOptional() {
        let value = try! tryArguments("required")
        let expected = TestOptions(intValue: 42, stringValue: "foobar", optionalStringValue: nil, optionalFilename: "filename", requiredName: "required", enabled: false, force: false, glob: false, arguments: [])
        XCTAssertEqual(value, expected)
    }

    func testArgumentsShouldSucceedWithoutSomeOptional() {
        let value = try! tryArguments("required", "--intValue", "3", "--optionalStringValue", "baz", "fuzzbuzz")
        let expected = TestOptions(intValue: 3, stringValue: "foobar", optionalStringValue: "baz", optionalFilename: "fuzzbuzz", requiredName: "required", enabled: false, force: false, glob: false, arguments: [])
        XCTAssertEqual(value, expected)
    }

    func testArgumentsShouldOverridePreviousOptional() {
        let value = try! tryArguments("required", "--intValue", "3", "--stringValue", "fuzzbuzz", "--intValue", "5", "--stringValue", "bazbuzz")
        let expected = TestOptions(intValue: 5, stringValue: "bazbuzz", optionalStringValue: nil, optionalFilename: "filename", requiredName: "required", enabled: false, force: false, glob: false, arguments: [])
        XCTAssertEqual(value, expected)
    }

    func testArgumentsEnableFlag() {
        let value = try! tryArguments("required", "--enabled", "--intValue", "3", "fuzzbuzz")
        let expected = TestOptions(intValue: 3, stringValue: "foobar", optionalStringValue: nil, optionalFilename: "fuzzbuzz", requiredName: "required", enabled: true, force: false, glob: false, arguments: [])
        XCTAssertEqual(value, expected)
    }

    func testArgumentsRedisableFlag() {
        let value = try! tryArguments("required", "--enabled", "--no-enabled", "--intValue", "3", "fuzzbuzz")
        let expected = TestOptions(intValue: 3, stringValue: "foobar", optionalStringValue: nil, optionalFilename: "fuzzbuzz", requiredName: "required", enabled: false, force: false, glob: false, arguments: [])
        XCTAssertEqual(value, expected)
    }

    func testArgumentsMultipleFlags() {
        let value = try! tryArguments("required", "-fg")
        let expected = TestOptions(intValue: 42, stringValue: "foobar", optionalStringValue: nil, optionalFilename: "filename", requiredName: "required", enabled: false, force: true, glob: true, arguments: [])
        XCTAssertEqual(value, expected)
    }

    func testArgumentsConsumeAllPositional() {
        let value = try! tryArguments("required", "optional", "value1", "value2")
        let expected = TestOptions(intValue: 42, stringValue: "foobar", optionalStringValue: nil, optionalFilename: "optional", requiredName: "required", enabled: false, force: false, glob: false, arguments: [ "value1", "value2" ])
        XCTAssertEqual(value, expected)
    }

    func testArgumentCheckForEndOfParameterList() {
        let value = try! tryArguments("--", "--intValue")
        let expected = TestOptions(intValue: 42, stringValue: "foobar", optionalStringValue: nil, optionalFilename: "filename", requiredName: "--intValue", enabled: false, force: false, glob: false, arguments: [])
        XCTAssertEqual(value, expected)
    }
}

struct TestOptions {
	let intValue: Int
	let stringValue: String
	let optionalStringValue: String?
	let optionalFilename: String
	let requiredName: String
	let enabled: Bool
	let force: Bool
	let glob: Bool
    let arguments: [String]
}

extension TestOptions: OptionsProtocol {

    enum Key { case intValue, stringValue, optionalStringValue, requiredName, optionalFilename, enabled, force, glob, arguments }

    static let all: DictionaryLiteral<Key, Argument> = [
        .intValue: .option(named: "intValue", defaultValue: 42, usage: "Some integer value"),
        .stringValue: .option(named: "stringValue", defaultValue: "foobar", usage: "Some string value"),
        .optionalStringValue: .option(named: "optionalStringValue", of: String.self, usage: "Some string value"),
        .requiredName: .positional(of: String.self, usage: "A name you're required to specify"),
        .optionalFilename: .positional(defaultValue: "filename", usage: "A filename that you can optionally specify"),
        .enabled: .option(named: "enabled", defaultValue: false, usage: "Whether to be enabled"),
        .force: .switch(named: "force", flag: "f", usage: "Whether to force"),
        .glob: .switch(named: "glob", flag: "g", usage: "Whether to glob"),
        .arguments: .list(of: String.self, usage: "An argument list that consumes the rest of positional arguments")
    ]

    init(parsedFrom arguments: ArgumentParser<TestOptions.Key>) throws {
        self.intValue = try arguments.value(for: .intValue)
        self.stringValue = try arguments.value(for: .stringValue)
        self.optionalStringValue = try arguments.value(for: .optionalStringValue)
        self.optionalFilename = try arguments.value(for: .optionalFilename)
        self.requiredName = try arguments.value(for: .requiredName)
        self.enabled = try arguments.value(for: .enabled)
        self.force = try arguments.value(for: .force)
        self.glob = try arguments.value(for: .glob)
        self.arguments = try arguments.value(for: .arguments)
    }

}

extension TestOptions: Equatable {

    static func ==(lhs: TestOptions, rhs: TestOptions) -> Bool {
        return lhs.intValue == rhs.intValue && lhs.stringValue == rhs.stringValue && lhs.optionalStringValue == rhs.optionalStringValue && lhs.optionalFilename == rhs.optionalFilename && lhs.requiredName == rhs.requiredName && lhs.enabled == rhs.enabled && lhs.force == rhs.force && lhs.glob == rhs.glob && lhs.arguments == rhs.arguments
    }

}

extension TestOptions: CustomStringConvertible {
	var description: String {
		return "{ intValue: \(intValue), stringValue: \(stringValue), optionalStringValue: \(optionalStringValue), optionalFilename: \(optionalFilename), requiredName: \(requiredName), enabled: \(enabled), force: \(force), glob: \(glob), arguments: \(arguments) }"
	}
}
