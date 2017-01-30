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
        case scalar(String, YAMLScalarStyle)
        case comment(String)
    }

    let kind: Kind
    let start: Mark

    init(_ kind: Kind, at start: Mark) {
        self.kind = kind
        self.start = start
    }

    var content: Kind {
        return kind
    }

    // MARK: -

    typealias Comment = AnyMarked<String>
    typealias Comments = (before: Comment?, after: Comment?)

    var comment: Comments

    // MARK: -

    var isSingleLine: Bool {
        switch kind {
        case .scalar, .value, .flowSequenceEnd, .flowMappingEnd:
            return true
        default:
            return false
        }
    }

    var isJSONFlowEnd: Bool {
        switch kind {
        case .flowSequenceEnd, .flowMappingEnd, .scalar(_, .singleQuoted), .scalar(_, .doubleQuoted):
            return true
        default:
            return false
        }
    }

    mutating func prependComments(_ otherComment: Comments) {
        var before = [Comment]()
        if let b1 = otherComment.before { before.append(b1) }
        if let b2 = otherComment.after { before.append(b2) }
        if let b3 = comment.before { before.append(b3) }
        comment.before = before.joined()
    }

}
