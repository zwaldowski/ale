//
//  Errors.swift
//  Command
//
//  Created by Justin Spahr-Summers on 10/24/2014.
//  Copyright © 2014 Carthage. All rights reserved.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

/// Possible errors that can originate from command-line parsing.
enum CommandLineError: Error {
    /// A command with the given verb was executed that has no handler.
    case unrecognizedCommand(String)

    /// A command was given an invalid argument `value`.
    case invalidArgument(usage: String, value: String)

    /// An option was given an invalid argument `value`.
    case invalidOption(key: String, value: String)

    /// A missing value for the argument by the given name.
    case expectedArgument(name: String)

    /// Unrecognized arguments remain.
    case unexpectedArguments([String])

    /// The value could not be converted for the command.
    case unexpectedValue(Any.Type)
}

extension CommandLineError: CustomStringConvertible {

    var description: String {
        switch self {
        case let .unrecognizedCommand(verb):
            return "Unrecognized command: '\(verb)'. See `\(CommandLine.executableName) help`."

        case let .invalidArgument(usage, value):
            return "Invalid value for argument '\(usage)': \(value)"

        case let .invalidOption(key, value):
            return "Invalid value for '--\(key)': \(value)"

        case let .expectedArgument(argumentName):
            return "Missing argument for \(argumentName)"

        case let .unexpectedArguments(options):
            return "Unrecognized arguments: \(options.joined(separator: ", "))"

        case let .unexpectedValue(type):
            return "Unrecognized attribute of type \(type)"
        }
    }

}
