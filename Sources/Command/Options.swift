//
//  Options.swift
//  Command
//
//  Created by Justin Spahr-Summers on 11/21/2014.
//  Copyright © 2015 Carthage. All rights reserved.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

/// Represents a record of options for a command, which can be parsed from
/// a list of command-line arguments.
///
/// Example:
///
///     struct LogOptions: OptionsProtocol {
///         let verbosity: Int
///         let outputFilename: String
///         let shouldDelete: Bool
///
///         enum Key { case verbosity, outputFilename, shouldDelete }
///
///         static let all: DictionaryLiteral<Key, Argument> = [
///             .verbosity: .option(named: "verbose", defaultValue: 0, usage: "the verbosity level with which to read the logs"),
///             .outputFilename: .option(named: "outputFilename", defaultValue: "", usage: "a file to print output to, instead of stdout"),
///             .shouldDelete: .switch(named: "delete", flag: "d", usage: "delete the logs when finished"),
///         ]
///
///         init(parsedFrom arguments: ArgumentParser<Key>) throws {
///             verbosity = try arguments.value(for: .verbosity)
///             outputFilename = try arguments.value(for: .outputFilename)
///             shouldDelete = try arguments.value(for: .shouldDelete)
///         }
///     }
///
public protocol OptionsProtocol {

    /// An enumerated list of the possible keys for this option type.
    associatedtype Key: Hashable

    /// Pairs describing all the possible attributes for this option type.
    static var all: DictionaryLiteral<Key, Argument> { get }

    /// Evaluates this set of options using the given command-line arguments.
    init(parsedFrom arguments: ArgumentParser<Key>) throws

}

/// An `OptionsProtocol` that has no options.
public struct NoOptions: OptionsProtocol {
    public enum Key: Hashable {
        public static func ==(lhs: Key, rhs: Key) -> Bool {
            return false
        }

        public var hashValue: Int {
            return 0
        }
    }

    public static var all: DictionaryLiteral<Key, Argument> {
        return [:]
    }

    public init(parsedFrom _: ArgumentParser<Key>) {}
}
