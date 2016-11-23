//
//  Command.swift
//  Command
//
//  Created by Justin Spahr-Summers on 10/10/2014.
//  Copyright © 2014 Carthage. All rights reserved.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import Foundation

/// Represents a subcommand that can be executed with its own set of arguments.
public protocol CommandProtocol: CustomStringConvertible {
	/// The command's options type.
	associatedtype Options: OptionsProtocol

	/// The action that users should specify to use this subcommand (e.g.,
	/// `help`).
	var verb: String { get }

	/// A human-readable, high-level description of what this command is used
	/// for.
	var function: String { get }

	/// Runs this subcommand with the given options.
	func run(_ options: Options) throws
}

extension CommandProtocol {

    public var description: String {
        var result = ""
        print(function, to: &result)
        for (_, attribute) in Options.all {
            print("\n", attribute, separator: "", to: &result)
        }
        return result
    }

}

/// Maintains the list of commands available to run.
public final class CommandRegistry {
	private var commandsByVerb: [String: AnyCommand] = [:]

	/// All available commands.
	public var commands: [AnyCommand] {
		return commandsByVerb.values.sorted { return $0.verb < $1.verb }
	}

	public init() {}

	/// Registers the given command, making it available to run.
	///
	/// If another command was already registered with the same `verb`, it will
	/// be overwritten.
	public func register<C: CommandProtocol>(_ command: C) {
		commandsByVerb[command.verb] = AnyCommand(command)
	}

	/// Runs the command corresponding to the given verb, passing it the given
	/// arguments.
	///
	/// Returns the results of the execution, or nil if no such command exists.
	public func run(command verb: String, arguments: [String]) throws {
        guard let command = self[verb] else {
            throw CommandLineError.unrecognizedCommand(verb)
        }

        try command.run(arguments: arguments)
	}

	/// Returns the command matching the given verb, or nil if no such command
	/// is registered.
	public subscript(verb: String) -> AnyCommand? {
		return commandsByVerb[verb]
	}
}

extension CommandRegistry {
	/// Hands off execution to the CommandRegistry, by parsing `arguments`
	/// and then running whichever command has been identified in the argument
	/// list.
	///
	/// If the chosen command executes successfully, the process will exit with
	/// a successful exit code.
	///
	/// If a matching command could not be found but there is any `executable-verb`
	/// style subcommand executable in the caller's `$PATH`, the subcommand will
	/// be executed.
	///
	/// If a matching command could not be found or a usage error occurred,
	/// a helpful error message will be written to `stderr`, then the process
	/// will exit with a failure error code.
    public func main<Command: CommandProtocol>(arguments: [String] = CommandLine.arguments, defaultCommand: Command) -> Never {
		assert(!arguments.isEmpty)

        let withoutProcess = arguments.dropFirst()
		let verb = withoutProcess.first ?? defaultCommand.verb
        let withoutVerb = Array(withoutProcess.dropFirst())

        do {
            try run(command: verb, arguments: withoutVerb)
        } catch CommandLineError.unrecognizedCommand(let verb) {
            if let subcommandExecuted = executeSubcommandIfExists(verb: verb, arguments: withoutVerb) {
                exit(subcommandExecuted)
            }

            print("Unrecognized command: '\(verb)'. See `\(CommandLine.executableName) help`.", to: &CommandLine.standardError)
            exit(EXIT_FAILURE)
        } catch {
            print(error, to: &CommandLine.standardError)
            exit(EXIT_FAILURE)
        }
        
        exit(EXIT_SUCCESS)
	}

	/// Finds and executes a subcommand which exists in your $PATH. The executable
	/// name must be in the form of `executable-verb`.
	///
	/// - Returns: The exit status of found subcommand or nil.
	private func executeSubcommandIfExists(verb: String, arguments: [String]) -> Int32? {
        let subcommand = "\(CommandLine.executableName)-\(verb)"

        guard Process.waitToExecute(atPath: "/usr/bin/which", arguments: [ "-s", subcommand ]) == 0 else {
            return nil
        }

		return Process.waitToExecute(atPath: "/usr/bin/env", arguments: [ subcommand ] + arguments)
	}
}
