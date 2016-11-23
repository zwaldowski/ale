//
//  ExistentialCommand.swift
//  Command
//
//  Created by Zachary Waldowski on 11/21/16.
//  Copyright © 2015 Carthage. All rights reserved.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

private class Box: CustomStringConvertible {
    var verb: String { fatalError() }
    var function: String { fatalError() }
    var description: String { fatalError() }
    func run(arguments: [String]) throws { fatalError() }
}

private final class ForwardedTo<Base: CommandProtocol>: Box {

    let base: Base
    init(base: Base) {
        self.base = base
    }

    override var verb: String {
        return base.verb
    }

    override var function: String {
        return base.function
    }

    override var description: String {
        return String(describing: base)
    }

    override func run(arguments: [String]) throws {
        let parser = ArgumentParser(for: Base.Options.self)
        try parser.parse(arguments: arguments)

        let options = try Base.Options(parsedFrom: parser)
        try base.run(options)
    }

}

/// A type-erased command.
public struct AnyCommand: CustomStringConvertible {

    private let box: Box

    /// Creates a command that wraps another.
    public init<Other: CommandProtocol>(_ base: Other) {
        if let other = base as? AnyCommand {
            self.box = other.box
        } else {
            self.box = ForwardedTo(base: base)
        }
    }

    /// Creates a command that wraps another.
    public init(_ other: AnyCommand) {
        self.box = other.box
    }

    /// The action that users should specify to use this subcommand (e.g.,
    /// `help`).
    public var verb: String {
        return box.verb
    }

    /// A human-readable, high-level description of what this command is used
    /// for.
    public var function: String {
        return box.function
    }

    /// Runs this subcommand by extracting options from `arguments`.
    func run(arguments: [String]) throws {
        return try box.run(arguments: arguments)
    }

    public var description: String {
        return String(describing: box)
    }

}
