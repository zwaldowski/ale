//
//  main.swift
//  ale
//
//  Created by Zachary Waldowski on 11/21/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import Command

struct TestCommand: CommandProtocol {

    struct Options: OptionsProtocol {
        let intValue: Int
        let stringValue: String
        let optionalStringValue: String?
        let flag: Bool

        enum Key { case intValue, stringValue, optionalStringValue, flag }

        static let all: DictionaryLiteral<Key, Argument> = [
            .intValue: .positional(defaultValue: 42, usage: "Some integer value"),
            .stringValue: .option(named: "stringValue", defaultValue: "foobar", usage: "Some string value"),
            .optionalStringValue: .option(named: "optionalStringValue", of: String.self, usage: "Some string value"),
            .flag: .switch(named: "flag", usage: "Turns the thing on")
        ]

        init(parsedFrom arguments: ArgumentParser<Key>) throws {
            intValue = try arguments.value(for: .intValue)
            stringValue = try arguments.value(for: .stringValue)
            optionalStringValue = try arguments.value(for: .optionalStringValue)
            flag = try arguments.value(for: .flag)
        }
    }

    var verb: String { return "verb" }
    var function: String { return "Test function test test test" }
    func run(_ options: Options) {}
}

let registry = CommandRegistry()
let help = HelpCommand(registry: registry)
registry.register(TestCommand())
registry.register(help)
registry.main(defaultCommand: help)
