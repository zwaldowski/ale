//
//  HelpCommand.swift
//  Command
//
//  Created by Justin Spahr-Summers on 10/10/2014.
//  Copyright © 2014 Carthage. All rights reserved.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

/// A basic implementation of a `help` command, using information available in a
/// `CommandRegistry`.
///
/// If you want to use this command, initialize it with the registry, then add
/// it to that same registry:
///
/// 	let commands = CommandRegistry()
/// 	let helpCommand = HelpCommand(registry: commands)
/// 	commands.register(helpCommand)
///
public struct HelpCommand: CommandProtocol {
    public struct Options: OptionsProtocol {
        fileprivate let verb: String?

        public enum Key { case verb }

        public static let all: DictionaryLiteral<Key, Argument> = [
            .verb: .positional(defaultValue: "", usage: "the command to display help for")
        ]

        public init(parsedFrom arguments: ArgumentParser<HelpCommand.Options.Key>) throws {
            self.verb = try arguments.value(for: .verb) { !$0.isEmpty }
        }
    }

	public let verb = "help"
	public let function = "Display general or command-specific help"

	private let registry: CommandRegistry

	/// Initializes the command to provide help from the given registry of
	/// commands.
	public init(registry: CommandRegistry) {
		self.registry = registry
	}

	public func run(_ options: Options) throws {
		if let verb = options.verb {
			if let command = self.registry[verb] {
                return print(command, to: &CommandLine.standardError)
			} else {
                print("Unrecognized command: '\(verb)'", to: &CommandLine.standardError)
			}
		}

		print("Available commands:\n")

		let maxVerbLength = self.registry.commands.map { $0.verb.characters.count }.max() ?? 0

		for command in self.registry.commands {
            let padding = String(repeating: " ", count: maxVerbLength - command.verb.characters.count)
			print("   \(command.verb)\(padding)   \(command.function)", to: &CommandLine.standardError)
		}
	}
}
