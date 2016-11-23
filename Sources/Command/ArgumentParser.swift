//
//  ArgumentParser.swift
//  Command
//
//  Created by Justin Spahr-Summers on 11/21/2014.
//  Copyright © 2014 Carthage. All rights reserved.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

/// Represents an argument passed on the command line.
private enum UnparsedArgument {
	/// A key corresponding to an option (e.g., `verbose` for `--verbose`).
	case key(String)

	/// A value, either associated with an option or passed as a positional
	/// argument.
	case value(String)

	/// One or more flag arguments (e.g 'r' and 'f' for `-rf`)
	case flag(Set<Character>)
}

extension UnparsedArgument: LosslessStringConvertible {

    init(_ stringValue: String) {
        if let dashes = stringValue.range(of: "--", options: .anchored) {
            // `--{key}`
            self = .key(stringValue[dashes.upperBound ..< stringValue.endIndex])
        } else if let dash = stringValue.range(of: "-", options: .anchored) {
            // `-{flags}`
            self = .flag(Set(stringValue.characters[dash.upperBound ..< stringValue.endIndex]))
        } else {
            // `{value}`
            self = .value(stringValue)
        }
    }

    var description: String {
        switch self {
        case let .key(key):
            return "--\(key)"

        case let .value(value):
            return "\"\(value)\""

        case let .flag(flags):
            return "-\(String(flags))"
        }
    }

}

protocol AnyArgumentParser: class {
    func consumeBoolean(forKey key: String) -> Bool?
    func consumeValue(forKey key: String) throws -> String?
    func consumePositionalArgument() -> String?
    func consume(key: String) -> Bool
    func consumeBoolean(flag: Character) -> Bool
}

/// Destructively parses a list of command-line arguments.
public final class ArgumentParser<Key: Hashable>: AnyArgumentParser {

    private let attributes: DictionaryLiteral<Key, Argument>
    private var unparsed = [UnparsedArgument]()
    private var parsed = [Key: Any]()

    /// Initializes the generator from a simple list of command-line arguments.
    public init<Options: OptionsProtocol>(for type: Options.Type) where Options.Key == Key {
        attributes = type.all
    }

    /// Populates the generator from a simple list of command-line arguments.
    public func parse(arguments rawArguments: [String]) throws {
        // The first instance of `--` terminates the option list.
        let params = rawArguments.split(maxSplits: 1, omittingEmptySubsequences: false) { $0 == "--" }

        // Parse out the keyed and flag options.
        unparsed.append(contentsOf: params[0].map(UnparsedArgument.init))

        // Remaining arguments are all positional parameters.
        if params.count == 2 {
            unparsed.append(contentsOf: params[1].map(UnparsedArgument.value))
        }

        for (key, attribute) in attributes {
            parsed[key] = try attribute.parseValue(arguments: self)
        }

        guard unparsed.isEmpty else {
            throw CommandLineError.unexpectedArguments(unparsed.map({ "\($0)" }))
        }
    }

	/// Returns whether the given key was enabled or disabled, or nil if it
	/// was not given at all.
	///
	/// If the key is found, it is then removed from the list of arguments
	/// remaining to be parsed.
	func consumeBoolean(forKey key: String) -> Bool? {
		let oldArguments = unparsed
		unparsed.removeAll()

        return oldArguments.reduce(nil) { (current, arg) -> Bool? in
            switch arg {
            case .key(key):
                return true
            case .key("no-\(key)"):
                return false
            default:
                unparsed.append(arg)
                return current
            }
        }
	}

	/// Returns the value associated with the given flag, or nil if the flag was
	/// not specified. If the key is presented, but no value was given, an error
	/// is returned.
	///
	/// If a value is found, the key and the value are both removed from the
	/// list of arguments remaining to be parsed.
	func consumeValue(forKey key: String) throws -> String? {
		let oldArguments = unparsed
		unparsed.removeAll()

		var foundValue: String?
		var index = 0

		while index < oldArguments.count {
			defer { index += 1 }
			let arg = oldArguments[index]

			guard case .key(key) = arg else {
				unparsed.append(arg)
				continue
			}

			index += 1
			guard index < oldArguments.count, case let .value(value) = oldArguments[index] else {
                throw CommandLineError.expectedArgument(name: "--\(key)")
			}

			foundValue = value
		}

		return foundValue
	}

	/// Returns the next positional argument that hasn't yet been returned, or
	/// nil if there are no more positional arguments.
	func consumePositionalArgument() -> String? {
		for (index, arg) in unparsed.enumerated() {
			if case let .value(value) = arg {
				unparsed.remove(at: index)
				return value
			}
		}

		return nil
	}

	/// Returns whether the given key was specified and removes it from the
	/// list of arguments remaining.
	func consume(key: String) -> Bool {
		let oldArguments = unparsed
		unparsed = oldArguments.filter {
            if case .key(key) = $0 { return false } else { return true }
        }

		return unparsed.count < oldArguments.count
	}

	/// Returns whether the given flag was specified and removes it from the
	/// list of arguments remaining.
	func consumeBoolean(flag: Character) -> Bool {
		for (index, arg) in unparsed.enumerated() {
			if case let .flag(flags) = arg, flags.contains(flag) {
				var flags = flags
				flags.remove(flag)

				if flags.isEmpty {
					unparsed.remove(at: index)
				} else {
					unparsed[index] = .flag(flags)
				}

				return true
			}
		}

		return false
	}

    /// Extracts a parsed argument.
    public func value<T>(for key: Key, of type: T.Type = T.self) throws -> T {
        switch parsed[key] {
        case let value as T:
            return value

        case let value?:
            throw CommandLineError.unexpectedValue(type(of: value))

        case nil:
            throw CommandLineError.expectedArgument(name: String(describing: key))
        }
    }

    /// Extracts a parsed argument, passing it through a validation `predicate`.
    public func value<T>(for key: Key, passingTest predicate: (T) throws -> Bool) throws -> T? {
        let originalValue = try value(for: key, of: T.self)
        guard try predicate(originalValue) else { return nil }
        return originalValue
    }

}
