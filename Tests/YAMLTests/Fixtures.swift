//
//  Fixtures.swift
//  ale
//
//  Created by Zachary Waldowski on 11/27/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import XCTest

#if SWIFT_PACKAGE
@testable import YAML
#else
@testable import ale
#endif

struct StringReader: Reader {

    private var iterator: String.UnicodeScalarView.Iterator
    private var offset = 0
    private var line = 1
    private var column = 1

    private(set) var peek: UnicodeScalar?

    /// Creates a scanner for iterating through `data`.
    init(string: String) {
        iterator = string.unicodeScalars.makeIterator()
    }

    mutating func advance() throws {
        switch iterator.next() {
        case let scalar? where CharacterSet.newlines.contains(scalar):
            peek = scalar
            offset += 1
            line += 1
            column = 0
        case let scalar?:
            peek = scalar
            offset += 1
            column += 1
        case nil:
            peek = nil
        }
    }

    var mark: Mark {
        return Mark(offset: offset, line: line, column: column)
    }

}

extension Token.Kind: Equatable {

    public static func == (lhs: Token.Kind, rhs: Token.Kind) -> Bool {
        switch (lhs, rhs) {
        case (.streamStart, .streamStart), (.streamEnd, .streamEnd), (.documentStart, .documentStart), (.documentEnd, .documentEnd), (.blockSequenceStart, .blockSequenceStart), (.blockMappingStart, .blockMappingStart), (.blockEnd, .blockEnd), (.flowSequenceStart, .flowSequenceStart), (.flowSequenceEnd, .flowSequenceEnd), (.flowMappingStart, .flowMappingStart), (.flowMappingEnd, .flowMappingEnd), (.blockEntry, .blockEntry), (.flowEntry, .flowEntry), (.key, .key), (.value, .value):
            return true

        case let (.versionDirective(lhs), .versionDirective(rhs)):
            return lhs == rhs

        case let (.tagDirective(lhs), .tagDirective(rhs)):
            return lhs == rhs

        case let (.alias(lhs), .alias(rhs)):
            return lhs == rhs

        case let (.anchor(lhs), .anchor(rhs)):
            return lhs == rhs

        case let (.tag(lhs), .tag(rhs)):
            return lhs == rhs

        case let (.scalar(lhs), .scalar(rhs)):
            return lhs == rhs

        case let (.comment(lhs), .comment(rhs)):
            return lhs == rhs

        default:
            return false
        }
    }

}
