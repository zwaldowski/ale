//
//  ArgumentValue.swift
//  Command
//
//  Created by Syo Ikeda on 12/14/2015.
//  Copyright © 2015 Carthage. All rights reserved.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

/// Represents a value that can be converted from a command-line argument.
public protocol ArgumentValue {
    /// A human-readable name for this type.
    static var usageName: String { get }

    /// Attempts to parse a value from the given command-line argument.
    init?(argument: String)
}

extension Int: ArgumentValue {
    public static let usageName = "integer"

    public init?(argument string: String) {
        self.init(string)
    }
}

extension String: ArgumentValue {
    public static let usageName = "string"

    public init(argument string: String) {
        self = string
    }
}

extension RawRepresentable where RawValue: ArgumentValue {

    public init?(argument string: String) {
        guard let rawValue = RawValue(argument: string) else { return nil }
        self.init(rawValue: rawValue)
    }

}
