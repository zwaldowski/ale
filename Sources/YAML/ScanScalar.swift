//
//  ScanScalar.swift
//  ale
//
//  Created by Zachary Waldowski on 1/29/17.
//  Copyright © 2017 Zachary Waldowski. All rights reserved.
//

import Foundation

protocol SubScanner {
    
    associatedtype Element

    mutating func scan(from reader: inout Reader, at start: Mark) throws -> Element

}

enum ScanScalarFilterResult {
    case allow
    case deny
    case end
}

enum FoldingState {
    case none
    case empty
    case moreIndented
}

protocol ScalarScanner: SubScanner {

    var style: YAMLScalarStyle { get }

    var indent: Int { get set }
    var scalars: String.UnicodeScalarView { get set }

    mutating func validate(_ current: UnicodeScalar?) throws -> ScanScalarFilterResult
    mutating func readEscape(from reader: inout Reader) throws -> ScanScalarFilterResult
    mutating func leadingLineSpaces(from reader: inout Reader) throws
    mutating func trailingLineSpaces()
    mutating func foldLines(before: FoldingState, after: FoldingState, isMoreIndented: Bool) throws
    mutating func chomp() -> String

    mutating func foundNonEmptyLine()
    mutating func foundOpeningBreak()
    mutating func foundLeadingFlowSpaces()

}

extension ScalarScanner {

    func readEscape(from _: inout Reader) -> ScanScalarFilterResult {
        return .allow
    }

    mutating func foldLines(before: FoldingState, after: FoldingState, isMoreIndented: Bool) {
        if after == .empty {
            scalars.append("\n")
        } else if before != .empty, after != .empty {
            scalars.append(" ")
        }
    }

    func foundNonEmptyLine() {}
    func foundOpeningBreak() {}
    func foundLeadingFlowSpaces() {}

}

extension ScalarScanner where Element == Token {

    // Scanning is done in three phases:
    //   1. Scan until newline
    //   2. Eat newline
    //   3. Scan leading blanks.
    //
    // Depending on the parameters given, we store, stop, or error in different
    // places in the above flow.
    mutating func scan(from reader: inout Reader, at start: Mark) throws -> Token {
        var lineFold = FoldingState.none

        building: while true {
            // Phase 1: scan until line ending
            phase1: while true {
                switch try validate(reader.head) {
                case .allow:
                    break
                case .deny:
                    try reader.advance()
                    continue phase1
                case .end:
                    break building
                }

                guard reader.head != nil else { break building }
                guard !reader.matches(characterFrom: .newlines) else { break phase1 }

                foundNonEmptyLine()
                foundOpeningBreak()

                // escape this?
                switch try readEscape(from: &reader) {
                case .allow:
                    break
                case .deny:
                    try reader.advance()
                    continue phase1
                case .end:
                    break phase1
                }

                // otherwise, just add the damn character
                scalars.append(reader.head!)
                try reader.advance()
            }

            // do we remove trailing whitespace?
            trailingLineSpaces()

            // Phase 2: eat line ending
            try reader.skipLineBreak()

            // Phase #3: scan leading spaces
            // first the required indentation...
            while reader.matches(characterFrom: .whitespaces), reader.mark.column <= indent {
                guard !reader.matches("\t") else {
                    throw YAMLParseError(.invalidIndentation, at: reader.mark)
                }
                try reader.advance()
            }

            // and then the rest of the whitespace
            try leadingLineSpaces(from: &reader)

            // was this an empty line?
            let nextLineFold: FoldingState = reader.matches(characterFrom: .newlines) ? .empty :
                reader.matches(characterFrom: .whitespaces) ? .moreIndented : .none

            try foldLines(before: lineFold, after: nextLineFold, isMoreIndented: reader.mark.column > indent)

            lineFold = nextLineFold
            foundOpeningBreak()

            // are we done via indentation?
            if lineFold != .empty, reader.mark.column <= indent {
                foundLeadingFlowSpaces()
                break
            }
        }

        // post-processing
        let spaces = chomp()
        var token = Token(.scalar(String(scalars), style), at: start)
        if !spaces.isEmpty {
            token.comment.after = Token.Comment("\(spaces)\n", at: reader.mark)
        }

        return token
    }

    mutating func trimTrailingWhitespace(after lastEscaped: String.UnicodeScalarIndex? = nil) {
        let deleteFrom = scalars.lastIndex(after: lastEscaped, where: CharacterSet.whitespaces.contains)
        scalars.removeSubrange(deleteFrom ..< scalars.endIndex)
    }

    mutating func stripTrailingNewlines() -> String {
        let deleteFrom = scalars.lastIndex(where: CharacterSet.newlines.contains)
        defer { scalars.removeSubrange(deleteFrom ..< scalars.endIndex) }
        return String(scalars.suffix(from: deleteFrom))
    }

    mutating func clipTrailingNewlines(after lastEscaped: String.UnicodeScalarIndex? = nil) -> String {
        var deleteFrom = scalars.lastIndex(after: lastEscaped, where: CharacterSet.newlines.contains)
        if deleteFrom != scalars.startIndex, deleteFrom != scalars.endIndex {
            scalars.formIndex(after: &deleteFrom)
        }
        defer { scalars.removeSubrange(deleteFrom ..< scalars.endIndex) }
        return String(scalars.suffix(from: deleteFrom))
    }

}

struct BlockScalarScanner: ScalarScanner {

    var indent: Int
    var scalars = String.UnicodeScalarView()

    private var foldedNewlineCount = 0
    private var didFoldedLineStartMoreIndented = false
    private var didFindOpeningBreak = false
    private var didFindNonEmptyLine = false

    private enum Chomping { case clip, strip, keep }

    private let detectIndent: Bool
    private let chompStyle: Chomping
    private let isFolded: Bool

    init(folded isFolded: Bool, headerFrom reader: inout Reader, currentIndent indent: Int?) throws {
        if try reader.skip("+") {
            (self.indent, self.detectIndent) = try reader.scanInteger().map { ($0, false) } ?? (1, true)
            self.chompStyle = .keep
        } else if try reader.skip("-") {
            (self.indent, self.detectIndent) = try reader.scanInteger().map { ($0, false) } ?? (1, true)
            self.chompStyle = .strip
        } else if let indent = try reader.scanInteger() {
            self.indent = indent
            self.detectIndent = false
            if try reader.skip("+") {
                self.chompStyle = .keep
            } else if try reader.skip("-") {
                self.chompStyle = .strip
            } else {
                self.chompStyle = .clip
            }
        } else {
            self.indent = 1
            self.detectIndent = true
            self.chompStyle = .clip
        }

        guard indent != 0 else {
            throw YAMLParseError(.invalidIndentation, at: reader.mark)
        }

        // Eat whitespaces and comments to the end of the line.
        try reader.skip(charactersFrom: .whitespaces)
        if reader.matches("#") {
            try reader.skip(untilCharactersFrom: .newlines)
        }

        // if it's not a line break, then we ran into a bad character inline
        guard reader.matches(characterFrom: .newlines) else {
            throw YAMLParseError(.expectedWhitespace, at: reader.mark)
        }

        // set the initial indentation
        if let indent = indent, indent >= 0 {
            self.indent += indent
        }

        self.isFolded = isFolded
    }

    var style: YAMLScalarStyle {
        return isFolded ? .folded : .literal
    }

    func validate(_: UnicodeScalar?) -> ScanScalarFilterResult {
        return .allow
    }

    mutating func leadingLineSpaces(from reader: inout Reader) throws {
        guard detectIndent, !didFindNonEmptyLine else { return }

        // update indent if we're auto-detecting
        while reader.matches(characterFrom: .whitespaces), !reader.matches("\t") {
            indent = max(indent, reader.mark.column)
            try reader.advance()
        }
    }

    func trailingLineSpaces() {}

    mutating func foldLines(before: FoldingState, after: FoldingState, isMoreIndented: Bool) {
        guard isFolded else {
            if didFindOpeningBreak {
                scalars.append("\n")
            }
            return
        }

        if foldedNewlineCount == 0, case .empty = after {
            didFoldedLineStartMoreIndented = before == .moreIndented
        }

        guard didFindOpeningBreak else { return }

        if case .none = before, case .none = after, isMoreIndented {
            scalars.append(" ")
        } else if case .empty = after {
            foldedNewlineCount += 1
        } else {
            scalars.append("\n")
        }

        if after != .empty, foldedNewlineCount > 0 {
            scalars.append(contentsOf: repeatElement("\n", count: foldedNewlineCount - 1))
            if didFoldedLineStartMoreIndented || after == .moreIndented || !didFindNonEmptyLine {
                scalars.append("\n")
            }
            foldedNewlineCount = 0
        }
    }

    mutating func chomp() -> String {
        switch chompStyle {
        case .strip:
            return stripTrailingNewlines()
        case .clip:
            return clipTrailingNewlines()
        case .keep:
            return ""
        }
    }

    mutating func foundNonEmptyLine() {
        didFindNonEmptyLine = true
    }

    mutating func foundOpeningBreak() {
        didFindOpeningBreak = true
    }

}

struct SingleQuotedScalarScanner: ScalarScanner {

    var indent = 0
    var scalars = String.UnicodeScalarView()
    var lastEscaped: String.UnicodeScalarIndex?

    init() {}

    var style: YAMLScalarStyle {
        return .singleQuoted
    }

    private var isEscaping = false

    mutating func validate(_ current: UnicodeScalar?) -> ScanScalarFilterResult {
        switch (current, isEscaping) {
        case ("'"?, true):
            scalars.append("'")
            isEscaping = false
            return .deny
        case (_, true):
            return .end
        case ("'"?, _):
            isEscaping = true
            return .deny
        default:
            isEscaping = false
            return .allow
        }
    }

    mutating func readEscape(from reader: inout Reader) throws -> ScanScalarFilterResult {
        guard try reader.skip("'") else { return .allow }
        guard reader.matches("'") else { return .end }
        lastEscaped = scalars.endIndex
        return .allow
    }

    func readEscape(from reader: inout Reader) throws -> UnicodeScalar? {
        return try reader.skip("'") && reader.skip("'") ? "'" : nil
    }

    func leadingLineSpaces(from reader: inout Reader) throws {
        try reader.skip(charactersFrom: .whitespaces)
    }

    mutating func trailingLineSpaces() {
        trimTrailingWhitespace(after: lastEscaped)
    }

    mutating func chomp() -> String {
        return clipTrailingNewlines(after: lastEscaped)
    }
    
}

struct DoubleQuotedScalarScanner: ScalarScanner {

    var indent = 0
    var scalars = String.UnicodeScalarView()
    var lastEscaped: String.UnicodeScalarIndex?

    private var hasEscapedLineBreak = false

    init() {}

    var style: YAMLScalarStyle {
        return .doubleQuoted
    }

    private var isAtEnd = false

    mutating func validate(_ current: UnicodeScalar?) -> ScanScalarFilterResult {
        if isAtEnd {
            return .end
        } else if current == "\"" {
            isAtEnd = true
            return .deny
        } else {
            return .allow
        }
    }

    mutating func readEscape(from reader: inout Reader) throws -> ScanScalarFilterResult {
        hasEscapedLineBreak = false
        guard try reader.skip("\\") else { return .allow }

        do {
            try scalars.append(reader.scanEscape())
            lastEscaped = scalars.endIndex
            return .deny
        } catch YAMLParseError.invalidEscape where reader.matches(characterFrom: .newlines) {
            hasEscapedLineBreak = true
            lastEscaped = scalars.endIndex
            try reader.advance()
            return .end
        }
    }

    func leadingLineSpaces(from reader: inout Reader) throws {
        try reader.skip(charactersFrom: .whitespaces)
    }

    mutating func trailingLineSpaces() {
        trimTrailingWhitespace(after: lastEscaped)
    }

    mutating func foldLines(before: FoldingState, after: FoldingState, isMoreIndented: Bool) {
        if after == .empty {
            scalars.append("\n")
        } else if before != .empty, after != .empty, !hasEscapedLineBreak {
            scalars.append(" ")
        }
    }

    mutating func chomp() -> String {
        return clipTrailingNewlines(after: lastEscaped)
    }

}

struct PlainScalarScanner: ScalarScanner {

    enum Prefix: UnicodeScalar {
        case negative = "-"
        case key = "?"
        case value = ":"
    }

    var indent = 0
    var scalars = String.UnicodeScalarView()

    private(set) var hasLeadingSpaces = false

    private let isInFlowContext: Bool

    init(prefix: Prefix? = nil, indent: Int, flowLevel: Int) {
        if let prefix = prefix?.rawValue {
            self.scalars.append(prefix)
        }
        self.indent = indent + 1
        self.isInFlowContext = flowLevel != 0
    }

    var style: YAMLScalarStyle {
        return .plain
    }

    private static let breakCharacters = CharacterSet(charactersIn: "?:,[]{}")

    enum DocumentIndicator: UnicodeScalar {
        case start = "-", end = "."
    }

    enum BreakDocumentState {
        case none
        case possible(DocumentIndicator, count: Int)
        case confirmed(DocumentIndicator)

        fileprivate mutating func reset(flushingTo scalar: inout String.UnicodeScalarView) {
            if case let .possible(kind, count) = self {
                scalar.append(contentsOf: repeatElement(kind.rawValue, count: count))
            }

            self = .none
        }

        fileprivate mutating func increment(_ kind: DocumentIndicator, flushingTo scalar: inout String.UnicodeScalarView) {
            switch self {
            case .possible(kind, let count):
                self = .possible(kind, count: count + 1)
            case let .possible(kind, count):
                scalar.append(contentsOf: repeatElement(kind.rawValue, count: count))
                fallthrough
            case .none:
                self = .possible(kind, count: 1)
            default:
                break
            }
        }
    }

    enum BreakValueState {
        case none
        case possible
        case confirmed

        fileprivate mutating func reset(flushingTo scalar: inout String.UnicodeScalarView) {
            if case .possible = self {
                scalar.append(":")
            }
            self = .none
        }
    }

    private(set) var needsDocument = BreakDocumentState.none
    private(set) var needsValue = BreakValueState.none
    private var mayBreakForComment = false

    mutating func validate(_ current: UnicodeScalar?) -> ScanScalarFilterResult {
        // Have we encountered something that looks like a document indicator?
        if case let .possible(kind, 3) = needsDocument, current == nil || CharacterSet.whitespacesAndNewlines.contains(current!) {
            needsDocument = .confirmed(kind)
            return .end
        } else if let kind = current.flatMap(DocumentIndicator.init) {

            needsValue.reset(flushingTo: &scalars)
            needsDocument.increment(kind, flushingTo: &scalars)
            return .deny
        }

        // If not, flush it.
        needsDocument.reset(flushingTo: &scalars)

        // At EOF?
        guard let current = current else {
            needsValue.reset(flushingTo: &scalars)
            mayBreakForComment = false
            return .end
        }

        // Have we encountered the ": " signifying a value paired with a key?
        if case .possible = needsValue, CharacterSet.whitespacesAndNewlines.contains(current) || isInFlowContext && PlainScalarScanner.breakCharacters.contains(current) {
            needsValue = .confirmed
            return .end
        } else if current == ":" {
            needsValue = .possible
            return .deny
        }

        // If not, flush it.
        needsValue.reset(flushingTo: &scalars)

        // How about a comment?
        if mayBreakForComment, current == "#" {
            return .end
        } else if CharacterSet.whitespaces.contains(current) {
            mayBreakForComment = true
            return .allow
        }

        // If not, flush it.
        mayBreakForComment = false

        // In the flow context, flow markers end plain scalars.
        return isInFlowContext && PlainScalarScanner.breakCharacters.contains(current) ? .end : .allow
    }

    func leadingLineSpaces(from reader: inout Reader) throws {
        try reader.skip(charactersFrom: .whitespaces)
    }

    mutating func trailingLineSpaces() {
        trimTrailingWhitespace()
    }

    mutating func chomp() -> String {
        // Remove trailing whitespace.
        let deleteFrom = scalars.lastIndex(where: CharacterSet.whitespaces.contains)
        let spaces = String(scalars.suffix(from: deleteFrom))
        scalars.removeSubrange(deleteFrom ..< scalars.endIndex)

        return stripTrailingNewlines() + spaces
    }

    mutating func foundLeadingFlowSpaces() {
        hasLeadingSpaces = true
    }

}

private extension BidirectionalCollection {

    func lastIndex(after lastEscaped: Index? = nil, where predicate: (Iterator.Element) throws -> Bool) rethrows -> Index {
        var index = endIndex
        while index != startIndex {
            formIndex(before: &index)

            guard try predicate(self[index]) else {
                formIndex(after: &index)
                break
            }
        }

        if let lastEscaped = lastEscaped, index < lastEscaped {
            return lastEscaped
        } else {
            return index
        }
    }
    
}
