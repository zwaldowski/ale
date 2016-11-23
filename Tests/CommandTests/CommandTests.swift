//
//  CommandTests.swift
//  Commandant
//
//  Created by Syo Ikeda on 1/5/16.
//  Copyright © 2016 Carthage. All rights reserved.
//

import XCTest

#if SWIFT_PACKAGE
import Command
#else
@testable import ale
#endif

class CommandTests: XCTestCase {

    func testUsageShouldNotCrashForNoOptions() {
        let command = NoOptionsCommand()

        let registry = CommandRegistry()
        registry.register(command)

        let wrapper = registry[command.verb]
        XCTAssertNotNil(wrapper)
        XCTAssertFalse(String(describing: wrapper!).isEmpty)
    }

    func testUsageInformation() {
        let usage = String(describing: TestCommand())
        XCTAssert(usage.contains("intValue"))
        XCTAssert(usage.contains("stringValue"))
        XCTAssert(usage.contains("name you're required to"))
        XCTAssert(usage.contains("optionally specify"))
    }

}

struct NoOptionsCommand: CommandProtocol {
	var verb: String { return "verb" }
	var function: String { return "function" }

	func run(_ options: NoOptions) {}
}

struct TestCommand: CommandProtocol {

    var verb: String { return "test" }
    var function: String { return "Test function" }
    func run(_ options: TestOptions) throws {}
    
}
