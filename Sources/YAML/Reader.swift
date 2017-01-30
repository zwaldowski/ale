//
//  Reader.swift
//  ale
//
//  Created by Zachary Waldowski on 11/23/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import Foundation

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

    associatedtype Content

    init(_ content: Content, at start: Mark)

    var content: Content { get }
    var start: Mark { get }

}

struct AnyMarked<Content>: Marked {

    let content: Content
    let start: Mark

    init(_ content: Content, at start: Mark) {
        self.content = content
        self.start = start
    }

}

extension BidirectionalCollection where Iterator.Element: Marked, Iterator.Element.Content == String {

    func joined() -> AnyMarked<Iterator.Element.Content>? {
        guard !isEmpty else { return nil }
        let content = lazy.map { $0.content }.joined(separator: "\n")
        let start = self[startIndex].start
        return AnyMarked(content, at: start)
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
    var head: UnicodeScalar? { get }

    /// Moves the head of the scanner.
    mutating func advance() throws

    /// A descriptor of the current position of the scanner.
    var mark: Mark { get }
}

// MARK: - Extensions

extension Reader {

    func matches(_ scalar: UnicodeScalar) -> Bool {
        return head == scalar
    }

    func matches(characterFrom characters: CharacterSet) -> Bool {
        return head.map(characters.contains) == true
    }

    mutating func match(charactersFrom set: CharacterSet) throws -> String {
        var scalars = String.UnicodeScalarView()
        while let current = head, set.contains(current) {
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
        while head.map(set.contains) == false {
            try advance()
        }
    }

    mutating func take(characterFrom set: CharacterSet) throws -> UnicodeScalar? {
        guard let current = head, set.contains(current) else { return nil }
        try advance()
        return current
    }

    mutating func scan(untilCharacterFrom set: CharacterSet) throws -> String {
        var scalars = String.UnicodeScalarView()
        while let current = head, !set.contains(current) {
            scalars.append(current)
            try advance()
        }
        return String(scalars)
    }


}
