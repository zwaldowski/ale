//
//  Reader.swift
//  ale
//
//  Created by Zachary Waldowski on 11/23/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import Foundation

/// Supported encodings for YAML.
///
/// - seealso: http://www.unicode.org/versions/Unicode9.0.0/ch03.pdf#G7404
public enum Encoding {
    /// An 8-bit encoding. A strict superset of ASCII.
    case utf8
    /// A 16-bit encoding delivered in Little Endian byte order.
    case utf16le
    /// A 16-bit encoding delivered in Big Endian byte order.
    case utf16be
    /// A 32-bit encoding delivered in Little Endian byte order.
    case utf32le
    /// A 32-bit encoding delivered in Big Endian byte order.
    case utf32be
}

// MARK: -

/// A location in a stream.
public struct Mark {
    /// The byte offset into the stream.
    let offset: Int
    /// The number of lines into the stream, broken by carriage returns.
    let line: Int
    /// The number of Unicode scalars into the line.
    let column: Int

    init(offset: Int, line: Int, column: Int) {
        self.offset = offset
        self.line = line
        self.column = column
    }
}

extension Mark: Comparable {

    public static func == (left: Mark, right: Mark) -> Bool {
        return left.offset == right.offset
    }

    public static func < (left: Mark, right: Mark) -> Bool {
        return left.offset < right.offset
    }

}

extension Mark: CustomDebugStringConvertible {

    public var debugDescription: String {
        return "\(line):\(column)"
    }

}

extension Mark: CustomReflectable {

    public var customMirror: Mirror {
        return Mirror(self, children: [
            "line": line,
            "column": column
        ], displayStyle: .tuple)
    }

}

// MARK: -

protocol Marked {
    
    associatedtype Context
    
    init(_ context: Context, in range: Range<Mark>)
    
    var range: Range<Mark> { get }
    
}

extension Marked {
    
    init(_ context: Context, at start: Mark) {
        self.init(context, in: start ..< start)
    }
    
}

struct AnyMarked<Context>: Marked {
    
    let value: Context
    let range: Range<Mark>
    
    init(_ value: Context, in range: Range<Mark>) {
        self.value = value
        self.range = range
    }
    
}

// MARK: -

/// Errors that arise from scanning a Unicode stream.
struct ReadError: Error {

    /// The kinds of error that may arise.
    enum Code {
        /// An invalid encoding or code point was detected.
        case invalidCodeUnit
    }

    /// The kind of error that arose.
    let code: Code

    /// The location in the stream at which the error arose.
    let mark: Mark

}

/// A type that incrementally decodes a stream of unicode for performing lexical
/// operations.
protocol Reader {
    /// The head of the scanner.
    var peek: UnicodeScalar? { get }

    /// Moves the head of the scanner.
    mutating func advance() throws

    /// A descriptor of the current position of the scanner.
    var mark: Mark { get }
}

// MARK: - Extensions

extension Reader {

    func matches(_ scalar: UnicodeScalar) -> Bool {
        return peek == scalar
    }

    func matches(characterFrom characters: CharacterSet) -> Bool {
        return peek.map(characters.contains) == true
    }
    
    mutating func match(charactersFrom set: CharacterSet) throws -> String {
        var scalars = String.UnicodeScalarView()
        while let current = peek, set.contains(current) {
            scalars.append(current)
            try advance()
        }
        return String(scalars)
    }
    
    @discardableResult
    mutating func skip(_ scalar: UnicodeScalar) throws -> Bool {
        guard matches(scalar) else { return false }
        try advance()
        return true
    }
    
    @discardableResult
    mutating func skip(characterFrom set: CharacterSet) throws -> Bool {
        guard matches(characterFrom: set) else { return false }
        try advance()
        return true
    }
    
    mutating func skip(charactersFrom set: CharacterSet) throws {
        while matches(characterFrom: set) {
            try advance()
        }
    }
    
    mutating func skip(untilCharactersFrom set: CharacterSet) throws {
        while peek.map(set.contains) == false {
            try advance()
        }
    }
    
    mutating func take(characterFrom set: CharacterSet) throws -> UnicodeScalar? {
        guard let current = peek, set.contains(current) else { return nil }
        try advance()
        return current
    }

    mutating func scan(untilCharacterFrom set: CharacterSet) throws -> String {
        var scalars = String.UnicodeScalarView()
        while let current = peek, !set.contains(current) {
            scalars.append(current)
            try advance()
        }
        return String(scalars)
    }
    
    mutating func scanLineBreak() throws -> String {
        switch peek {
        case "\n"?, "\u{2028}"?, "\u{2029}"?:
            let ret = String(peek!)
            try advance()
            return ret
        case "\r"?, "\u{0085}"?:
            try advance()
            try skip("\n")
            return "\n"
        default:
            return ""
        }
    }
    
    @discardableResult
    mutating func skipLineBreak() throws -> Bool {
        guard matches(characterFrom: .newlines) else { return false }
        try advance()
        try skip("\n")
        return true
    }
    
}
