//
//  Argument.swift
//  Command
//
//  Created by Zachary Waldowski on 11/22/16.
//  Copyright © 2015 Carthage. All rights reserved.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

/// Describes an argument that can be provided on the command line.
public struct Argument: CustomStringConvertible {

    private enum Kind {
        case positional(ArgumentValue.Type, defaultValue: Any?)
        case list(ArgumentValue.Type)
        case option(String, defaultValue: Bool)
        case parameter(String, ArgumentValue.Type, defaultValue: Any)
        case `switch`(String, flag: Character?)
    }

    private let kind: Kind

    /// A human-readable string describing the purpose of this option. This will
    /// be shown in help messages.
    ///
    /// For boolean operations, this should describe the effect of _not_ using
    /// the default value (i.e., what will happen if you disable/enable the flag
    /// differently from the default).
    let usage: String

    private init(kind: Kind, usage: String) {
        self.kind = kind
        self.usage = usage
    }

    /// Creates a descriptor for evaluating an argument.
    ///
    /// An argument is an unlabelled positional value passed in. All positional
    /// arguments are parsed in order without respect to options or flags.
    ///
    /// If no value was specified on the command line, `defaultValue` is used.
    public static func positional<T: ArgumentValue>(of _: T.Type = T.self, defaultValue: T? = nil, usage: String) -> Argument {
        return Argument(kind: .positional(T.self, defaultValue: defaultValue), usage: usage)
    }

    /// Creates a descriptor for evaluating an argument list.
    ///
    /// An argument list consumes all remaining arguments on the command line.
    /// These do not include remaining options or flags.
    ///
    /// If no values were specified on the command line, `[]` is parsed.
    public static func list<T: ArgumentValue>(of: T.Type = T.self, usage: String) -> Argument {
        return Argument(kind: .list(T.self), usage: usage)
    }

    /// Creates a descriptor for a command line parameter.
    ///
    /// An option is a key-value pair passed on the command line as
    /// `--key value`, and does not count as an argument.
    ///
    /// If no value was specified on the command line, `defaultValue` is used.
    public static func option<T: ArgumentValue>(named name: String, defaultValue: T, usage: String) -> Argument {
        return Argument(kind: .parameter(name, T.self, defaultValue: defaultValue), usage: usage)
    }

    /// Creates a descriptor for a command line parameter.
    ///
    /// An option is a key-value pair passed on the command line as
    /// `--key value`, and does not count as an argument.
    ///
    /// If no value was specified on the command line, `nil` is used.
    public static func option<T: ArgumentValue>(named name: String, of: T.Type = T.self, usage: String) -> Argument {
        return Argument(kind: .parameter(name, T.self, defaultValue: Optional<T>.none as Any), usage: usage)
    }

    /// Creates a descriptor for a boolean command line option.
    ///
    /// A boolean option is activated by `--key` and deactivated by `--no-key`.
    /// The lattermost version of these options is the one that is used.
    ///
    /// If no value was specified on the command line, `defaultValue` is used.
    public static func option(named name: String, defaultValue: Bool = false, usage: String) -> Argument {
        return Argument(kind: .option(name, defaultValue: defaultValue), usage: usage)
    }

    /// Creates a descriptor for a parameterless command line flag.
    ///
    /// Flags default to `false` and may only be switched on. Canonical examples
    /// include `--force` and `--recurse`.
    ///
    /// An optional `flag` may be used to enable the switch. For example, `-v`
    /// would be shorthand for `--verbose`.
    ///
    /// Multiple flags can be grouped together as a single argument and will
    /// split when parsing. For example, in `rm -rf`, 'r' and 'f' would be
    /// treated as individual flags.
    ///
    /// For a toggle that can be enabled and disabled, prefer an `option`.
    public static func `switch`(named name: String, flag: Character? = nil, usage: String) -> Argument {
        return Argument(kind: .switch(name, flag: flag), usage: usage)
    }

//    var example: String {
//
//    }

    public var description: String {
        let example: String
        let required: Bool

        switch kind {
        case let .positional(_, defaultValue?):
            example = "\(defaultValue)"
            required = false
        case let .positional(type, _):
            example = "(\(type.usageName))"
            required = true

        case let .list(type):
            example = "(\(type.usageName))"
            required = false

        case let .option(key, flag):
            example = flag ? "--no-\(key)" : "--\(key)"
            required = false

        case let .parameter(key, type, _):
            example = "--\(key) (\(type.usageName))"
            required = false

        case let .switch(key, flag?):
            example = "--\(key)|-\(flag)"
            required = false
        case let .switch(key, nil):
            example = "--\(key)"
            required = false
        }

        var usage = self.usage
        usage.enumerateSubstrings(in: usage.startIndex ..< usage.endIndex, options: [.byLines, .reverse]) { (_, range, _, _) in
            usage.insert("\t", at: range.lowerBound)
        }

        if required {
            return "\(example)\n\(usage)"
        } else {
            return "[\(example)]\n\(usage)"
        }
    }

    func parseValue(arguments: AnyArgumentParser) throws -> Any {
        switch kind {
        case let .positional(type, defaultValue):
            guard let stringValue = arguments.consumePositionalArgument() else {
                if let defaultValue = defaultValue {
                    return defaultValue
                } else {
                    throw CommandLineError.expectedArgument(name: usage)
                }
            }

            guard let value = type.init(argument: stringValue) else {
                throw CommandLineError.invalidArgument(usage: usage, value: stringValue)
            }

            return value

        case let .list(type):
            var values = [ArgumentValue]()

            while let nextValue = arguments.consumePositionalArgument() {
                guard let value = type.init(argument: nextValue) else {
                    throw CommandLineError.invalidArgument(usage: usage, value: nextValue)
                }

                values.append(value)
            }

            return values

        case let .option(key, defaultValue):
            return arguments.consumeBoolean(forKey: key) ?? defaultValue

        case let .parameter(key, type, defaultValue):
            guard let stringValue = try arguments.consumeValue(forKey: key) else {
                return defaultValue
            }

            guard let value = type.init(argument: stringValue) else {
                throw CommandLineError.invalidOption(key: key, value: stringValue)
            }

            return value

        case let .switch(key, flag):
            let enabled = arguments.consume(key: key)
            if let flag = flag {
                return arguments.consumeBoolean(flag: flag)
            }
            return enabled
        }
    }

}
