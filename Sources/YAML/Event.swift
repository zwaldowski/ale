//
//  Event.swift
//  ale
//
//  Created by Zachary Waldowski on 11/23/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

extension YAMLParser {

    /// Elements produced by parsing a YAML stream.
    public struct Event: Marked {

        /// The type of node described by the event, and any associated data.
        public enum Kind {
            /// The beginning of one of potentially many YAML documents.
            case documentStart(version: (Int, Int), tags: [String: String])
            /// The start of an array or list.
            case sequenceStart(anchor: String, tag: String, style: YAMLCollectionStyle)
            /// The end of an array or list.
            case sequenceEnd
            /// The start of a dictionary or hash.
            case mappingStart(anchor: String, tag: String, style: YAMLCollectionStyle)
            /// The end of a dictionary or hash.
            case mappingEnd
            /// A string or number.
            case scalar(anchor: String, tag: String, content: String, style: YAMLScalarStyle)
            /// Points to the most recent node in the stream named `anchor`.
            case alias(anchor: String)
            /// The end of the current document in the stream.
            case documentEnd
        }

        /// The type of this node.
        public let kind: Kind
        let start: Mark

        init(_ kind: Kind, at start: Mark) {
            self.kind = kind
            self.start = start
        }

        var content: Kind {
            return kind
        }

        // MARK: -

        typealias Comments = (before: String?, after: String?)

        /// Some events may be occur in the stream without being tied to
        /// any characters in the input.
        public var isImplicit = false
        var comment: Comments

    }

}

// MARK: -

extension YAMLParser.Event {

    init(nullAt mark: Mark, anchor: String = "", tag: String = "") {
        self.init(.scalar(anchor: anchor, tag: tag, content: "", style: .plain), at: mark)
        isImplicit = true
    }

    mutating func readComments(from token: Token) {
        comment = (token.comment.before?.content, token.comment.after?.content)
    }

}
