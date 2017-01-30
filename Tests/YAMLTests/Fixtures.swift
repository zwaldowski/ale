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
    private var offset = -1
    private var line = 1
    private var column = 0

    private(set) var head: UnicodeScalar?

    /// Creates a scanner for iterating through `data`.
    init(string: String) {
        iterator = string.unicodeScalars.makeIterator()
    }

    mutating func advance() throws {
        if matches(characterFrom: .newlines) {
            line += 1
            column = 0
        }

        head = iterator.next()

        if head != nil {
            offset += 1
            column += 1
        }
    }

    var mark: Mark {
        return Mark(offset: max(offset, 0), line: line, column: max(column, 1))
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
