//
//  Token.swift
//  ale
//
//  Created by Zachary Waldowski on 11/23/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

struct Token: Marked {

    enum Kind {
        case streamStart
        case streamEnd
        case versionDirective(major: Int, minor: Int)
        case tagDirective(handle: String, prefix: String)
        case documentStart
        case documentEnd
        case blockSequenceStart
        case blockMappingStart
        case blockEnd
        case flowSequenceStart
        case flowSequenceEnd
        case flowMappingStart
        case flowMappingEnd
        case blockEntry
        case flowEntry
        case key
        case value
        case alias(String)
        case anchor(String)
        case tag(handle: String, suffix: String)
        case scalar(String, ScalarStyle)
        case comment(String)
    }

    let kind: Kind
    let range: Range<Mark>

    init(_ kind: Kind, in range: Range<Mark>) {
        self.kind = kind
        self.range = range
    }

    // MARK: -
    
    typealias Comment = AnyMarked<String>

    var comment: (before: Comment?, after: Comment?)

    var isSingleLine: Bool {
        switch kind {
        case .scalar, .value, .flowSequenceEnd, .flowMappingEnd:
            return true
        default:
            return false
        }
    }

}
