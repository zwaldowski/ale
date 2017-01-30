//
//  Parser.swift
//  ale
//
//  Created by Zachary Waldowski on 12/5/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

/// A YAML parser accepts a stream of characters (formally, a Unicode scalar
/// value) and produces a series of events that can be used to build a node
/// in a serialized tree.
public struct YAMLParser {

    /// Errors that arise from parsing a YAML stream.
    public typealias Error = YAMLParseError

    private var scanner: Scanner

    init(reader: Reader) {
        self.scanner = Scanner(reader: reader)
    }

    // MARK: - State

    private enum State {
        case start
        case documentStart(implicit: Bool)
        case documentContent
        case blockNode
        case blockSequenceEntry
        case indentlessSequenceEntry
        case blockMappingKey
        case blockMappingValue
        case flowSequenceEntry(first: Bool)
        case flowSequenceEntryMappingKey, flowSequenceEntryMappingValue, flowSequenceEntryMappingEnd
        case flowMappingKey(first: Bool)
        case flowMappingValue(empty: Bool)
        case documentEnd
        case end(mark: Mark)
    }

    private typealias StateStackEntry = (state: State, mark: Mark)

    private var states = [StateStackEntry]()
    private var state = State.start

    private mutating func pushState(_ state: State, for token: Token) {
        states.append((state, token.start))
        deferredToken = token
    }

    @discardableResult
    private mutating func popState() -> Mark? {
        let entry = states.popLast()
        state = entry?.state ?? .documentEnd
        return entry?.mark
    }

    /// Returns the next event in the stream, up to and including the stream's
    /// end.
    ///
    /// May throw an error due to malformed input, or attempting to read past
    /// the end of the stream.
    public mutating func next() throws -> Event {
        switch state {
        case .start: return try streamStart()
        case .documentStart(let implicit): return try documentStart(implicit: implicit)
        case .documentContent: return try documentContent()
        case .blockNode: return try node(style: .block)
        case .blockSequenceEntry: return try blockSequenceEntry()
        case .indentlessSequenceEntry: return try indentlessSequenceEntry()
        case .blockMappingKey: return try blockMappingKey()
        case .blockMappingValue: return try blockMappingValue()
        case .flowSequenceEntry(let first): return try flowSequenceEntry(first: first)
        case .flowSequenceEntryMappingKey: return try flowSequenceEntryMappingKey()
        case .flowSequenceEntryMappingValue: return try flowSequenceEntryMappingValue()
        case .flowSequenceEntryMappingEnd: return try flowSequenceEntryMappingEnd()
        case .flowMappingKey(let first): return try flowMappingKey(first: first)
        case .flowMappingValue(let empty): return try flowMappingValue(empty: empty)
        case .documentEnd: return try documentEnd()
        case .end(let mark): throw Error(.endOfStream, at: mark)
        }
    }

    // MARK: - Tokens

    private var deferredToken: Token?
    private var deferredComment: Token.Comments

    private mutating func nextToken() throws -> Token {
        var token: Token
        if let deferred = deferredToken {
            deferredToken = nil
            token = deferred
        } else {
            token = try scanner.next()
        }

        token.prependComments(deferredComment)
        deferredComment = (nil, nil)

        return token
    }

    // MARK: - Top-Level

    // stream    ::= STREAM-START implicit_document? explicit_document*
    //                                                               STREAM-END
    // implicit_document ::= block_node DOCUMENT-END*
    // explicit_document ::= DIRECTIVE* DOCUMENT-START block_node? DOCUMENT-END*

    private mutating func streamStart() throws -> Event {
        let token = try nextToken()
        guard case .streamStart = token.kind else {
            throw Error(.invalidToken, at: token.start)
        }

        deferredComment = token.comment

        return try documentStart(implicit: true)
    }

    private static let defaultVersion = (1, 2)
    private static let defaultTags = [
        "!": "!",
        "!!": "tag:yaml.org,2002:",
    ]

    private var tags: [String: String] = [:]

    private mutating func documentStart(implicit: Bool) throws -> Event {
        var token = try nextToken()

        // Skip any extra DOCUMENT-END
        if !implicit {
            while case .documentEnd = token.kind {
                token = try nextToken()
            }
        }

        switch token.kind {
        case .streamEnd:
            state = .end(mark: token.start)
            throw Error(.endOfStream, at: token.start)
        case .versionDirective, .tagDirective, .documentStart,
             _ where !implicit:
            tags.removeAll()
            
            var version: (Int, Int)?
            let start = token.start

            while true {
                switch token.kind {
                case let .versionDirective(major, minor):
                    guard major == 1 else { throw Error(.invalidVersion, at: token.start) }
                    guard version == nil else { throw Error(.unexpectedDirective, at: token.start) }

                    version = (major, minor)
                    token = try nextToken()
                case let .tagDirective(handle, prefix):
                    guard tags.updateValue(prefix, forKey: handle) == nil else {
                        throw Error(.unexpectedDirective, at: token.start)
                    }
                    token = try nextToken()
                case .documentStart:
                    state = .documentContent

                    for (key, value) in YAMLParser.defaultTags where tags.index(forKey: key) == nil {
                        tags[key] = value
                    }

                    var event = Event(.documentStart(version: version ?? YAMLParser.defaultVersion, tags: tags), at: start)
                    event.readComments(from: token)
                    return event
                default:
                    throw Error(.invalidToken, at: token.start)
                }
            }
        default:
            pushState(.documentEnd, for: token)
            state = .blockNode

            tags = YAMLParser.defaultTags

            var event = Event(.documentStart(version: YAMLParser.defaultVersion, tags: tags), at: token.start)
            event.isImplicit = true
            return event
        }
    }

    private mutating func documentEnd() throws -> Event {
        let token = try nextToken()

        guard case .documentEnd = token.kind else {
            deferredToken = token
            state = .documentStart(implicit: true)

            var event = Event(.documentEnd, at: token.start)
            event.isImplicit = true
            return event
        }

        state = .documentStart(implicit: false)

        var event = Event(.documentEnd, at: token.start)
        event.readComments(from: token)
        return event
    }

    private mutating func documentContent() throws -> Event {
        let token = try nextToken()

        switch token.kind {
        case .tagDirective, .versionDirective, .documentStart, .documentEnd,
             .streamEnd:
            popState()
            return Event(nullAt: token.start)
        default:
            deferredToken = token
            return try node(style: .block)
        }
    }

    // MARK: - Nodes

    // block_node_or_indentless_sequence ::= ALIAS
    //               | properties (block_content | indentless_block_sequence)?
    //               | block_content
    //               | indentless_block_sequence
    // block_node    ::= ALIAS
    //                   | properties block_content?
    //                   | block_content
    // flow_node     ::= ALIAS
    //                   | properties flow_content?
    //                   | flow_content
    // properties    ::= TAG ANCHOR? | ANCHOR TAG?
    // block_content     ::= block_collection | flow_collection | SCALAR
    // flow_content      ::= flow_collection | SCALAR
    // block_collection  ::= block_sequence | block_mapping
    // flow_collection   ::= flow_sequence | flow_mapping

    private func canonicalTag(handle: String, suffix: String) -> String {
        return "\(tags[handle] ?? handle)\(suffix)"
    }

    private mutating func node(style: YAMLCollectionStyle, indentless indentlessSequence: Bool = false) throws -> Event {
        var token = try nextToken()
        var anchor = ""
        var tag = ""
        let start = token.start

        // Parse properties
        switch token.kind {
        case let .alias(name):
            popState()
            return Event(.alias(anchor: name), at: token.start)
        case let .anchor(name):
            anchor = name
            token = try nextToken()

            if case let .tag(handle, suffix) = token.kind {
                tag = canonicalTag(handle: handle, suffix: suffix)
                token = try nextToken()
            }
        case let .tag(handle, suffix):
            tag = canonicalTag(handle: handle, suffix: suffix)
            token = try nextToken()

            if case .anchor(let name) = token.kind {
                anchor = name
                token = try nextToken()
            }
        default:
            break
        }

        switch (token.kind, style) {
        case (.blockEntry, _) where indentlessSequence:
            state = .indentlessSequenceEntry
            deferredToken = token
            return Event(.sequenceStart(anchor: anchor, tag: tag, style: .block), at: start)
        case let (.scalar(content, style), _):
            popState()

            var event = Event(.scalar(anchor: anchor, tag: tag, content: content, style: style), at: start)
            event.readComments(from: token)
            return event
        case (.flowSequenceStart, _):
            state = .flowSequenceEntry(first: true)
            return Event(.sequenceStart(anchor: anchor, tag: tag, style: .flow), at: start)
        case (.flowMappingStart, _):
            state = .flowMappingKey(first: true)
            return Event(.mappingStart(anchor: anchor, tag: tag, style: .flow), at: start)
        case (.blockSequenceStart, .block):
            state = .blockSequenceEntry

            var event = Event(.sequenceStart(anchor: anchor, tag: tag, style: .block), at: start)
            event.readComments(from: token)
            return event
        case (.blockMappingStart, .block):
            state = .blockMappingKey

            var event = Event(.mappingStart(anchor: anchor, tag: tag, style: .block), at: start)
            event.readComments(from: token)
            return event
        case _ where !tag.isEmpty || !anchor.isEmpty:
            popState()

            deferredToken = token

            var event = Event(nullAt: token.start, anchor: anchor, tag: tag)
            event.readComments(from: token)
            return event
        default:
            throw Error(.invalidToken, at: start)
        }
    }

    // MARK: - Block Sequences

    // block_sequence ::= BLOCK-SEQUENCE-START (BLOCK-ENTRY block_node?)*
    //                                                               BLOCK-END

    private mutating func blockSequenceEntry() throws -> Event {
        let token = try nextToken()
        switch token.kind {
        case .blockEnd:
            popState()

            var event = Event(.sequenceEnd, at: token.start)
            event.readComments(from: token)
            return event
        case .blockEntry:
            let token = try nextToken()
            switch token.kind {
            case .blockEntry, .blockEnd:
                state = .blockSequenceEntry
                deferredToken = token
                return Event(nullAt: token.start)
            default:
                pushState(.blockSequenceEntry, for: token)
                return try node(style: .block)
            }
        default:
            throw Error(.unexpectedValue, at: token.start)
        }
    }

    // MARK: - Indentless Sequences

    // indentless_sequence ::= (BLOCK-ENTRY block_node?)+
    // indentless_sequence?
    // sequence:
    // - entry
    //  - nested

    private mutating func indentlessSequenceEntry() throws -> Event {
        var token = try nextToken()
        guard case .blockEntry = token.kind else {
            popState()
            deferredToken = token
            return Event(.sequenceEnd, at: token.start)
        }

        deferredComment = token.comment
        token = try nextToken()

        switch token.kind {
        case .blockEntry, .key, .value, .blockEnd:
            state = .indentlessSequenceEntry
            return Event(nullAt: token.start)
        default:
            pushState(.indentlessSequenceEntry, for: token)
            return try node(style: .block)
        }
    }

    // MARK: - Block Mapping

    // block_mapping     ::= BLOCK-MAPPING_START
    //                       ((KEY block_node_or_indentless_sequence?)?
    //                       (VALUE block_node_or_indentless_sequence?)?)*
    //                       BLOCK-END

    private mutating func blockMappingKey() throws -> Event {
        let token = try nextToken()
        switch token.kind {
        case .key:
            deferredComment = token.comment

            let token = try nextToken()
            switch token.kind {
            case .key, .value, .blockEnd:
                state = .blockMappingValue
                return Event(nullAt: token.start)
            default:
                pushState(.blockMappingValue, for: token)
                deferredToken = token
                
                return try node(style: .block, indentless: true)
            }
        case .value:
            state = .blockMappingValue
            return Event(nullAt: token.start)
        case .blockEnd:
            popState()
            deferredComment = token.comment
            return Event(.mappingEnd, at: token.start)
        default:
            throw Error(.expectedKey, at: token.start)
        }
    }

    private mutating func blockMappingValue() throws -> Event {
        var token = try nextToken()

        guard case .value = token.kind else {
            state = .blockMappingKey
            deferredToken = token

            return Event(nullAt: token.start)
        }

        deferredComment = token.comment
        token = try nextToken()

        switch token.kind {
        case .key, .value, .blockEnd:
            state = .blockMappingKey
            return Event(nullAt: token.start)
        default:
            pushState(.blockMappingKey, for: token)
            return try node(style: .block, indentless: true)
        }
    }

    // MARK: - Flow Sequence

    // flow_sequence     ::= FLOW-SEQUENCE-START
    //                       (flow_sequence_entry FLOW-ENTRY)*
    //                       flow_sequence_entry?
    //                       FLOW-SEQUENCE-END
    // flow_sequence_entry   ::= flow_node | KEY flow_node? (VALUE flow_node?)?
    //
    // Note that while production rules for both flow_sequence_entry and
    // flow_mapping_entry are equal, their interpretations are different.
    // For `flow_sequence_entry`, the part `KEY flow_node? (VALUE flow_node?)?`
    // generate an inline mapping (set syntax).

    private mutating func flowSequenceEntry(first: Bool) throws -> Event {
        var token = try nextToken()
        switch token.kind {
        case .flowSequenceEnd:
            popState()

            var event = Event(.sequenceEnd, at: token.start)
            event.readComments(from: token)
            return event
        case .flowEntry where !first:
            token = try nextToken()
        case _ where !first:
            throw Error(.expectedValue, at: token.start)
        default:
            break
        }

        switch token.kind {
        case .value:
            deferredToken = token
            fallthrough
        case .key:
            state = .flowSequenceEntryMappingKey

            return Event(.mappingStart(anchor: "", tag: "", style: .flow), at: token.start)
        case .flowSequenceEnd:
            popState()

            var event = Event(.sequenceEnd, at: token.start)
            event.readComments(from: token)
            return event
        default:
            pushState(.flowSequenceEntry(first: false), for: token)
            return try node(style: .flow)
        }
    }

    private mutating func flowSequenceEntryMappingKey() throws -> Event {
        let token = try nextToken()
        switch token.kind {
        case .value, .flowEntry, .flowSequenceEnd:
            state = .flowSequenceEntryMappingValue
            deferredToken = token
            return Event(nullAt: token.start)
        default:
            pushState(.flowSequenceEntryMappingValue, for: token)
            return try node(style: .flow)
        }
    }

    private mutating func flowSequenceEntryMappingValue() throws -> Event {
        var token = try nextToken()
        guard case .value = token.kind else {
            state = .flowSequenceEntryMappingEnd
            deferredToken = token
            return Event(nullAt: token.start)
        }

        token = try nextToken()
        switch token.kind {
        case .flowEntry, .flowSequenceEnd:
            state = .flowSequenceEntryMappingEnd
            return Event(nullAt: token.start)
        default:
            pushState(.flowSequenceEntryMappingEnd, for: token)
            return try node(style: .flow)
        }
    }

    private mutating func flowSequenceEntryMappingEnd() throws -> Event {
        let token = try nextToken()

        state = .flowSequenceEntry(first: false)
        deferredToken = token

        return Event(.mappingEnd, at: token.start)
    }

    // MARK: - Flow Mapping

    // flow_mapping  ::= FLOW-MAPPING-START
    //                   (flow_mapping_entry FLOW-ENTRY)*
    //                   flow_mapping_entry?
    //                   FLOW-MAPPING-END
    // flow_mapping_entry    ::= flow_node | KEY flow_node? (VALUE flow_node?)?

    private mutating func flowMappingKey(first: Bool) throws -> Event {
        var token = try nextToken()
        switch token.kind {
        case .flowMappingEnd:
            popState()

            var event = Event(.mappingEnd, at: token.start)
            event.readComments(from: token)
            return event
        case .flowEntry where !first:
            token = try nextToken()
        case _ where first:
            break
        default:
            throw Error(.expectedKey, at: token.start)
        }

        switch token.kind {
        case .key:
            let token = try nextToken()
            switch token.kind {
            case .value, .flowEntry, .flowMappingEnd:
                deferredToken = token
                state = .flowMappingValue(empty: false)
                return Event(nullAt: token.start)
            default:
                pushState(.flowMappingValue(empty: false), for: token)
                return try node(style: .flow)
            }
        case .value:
            deferredToken = token
            state = .flowMappingValue(empty: false)
            return Event(nullAt: token.start)
        case .flowMappingEnd:
            popState()

            var event = Event(.mappingEnd, at: token.start)
            event.readComments(from: token)
            return event
        default:
            pushState(.flowMappingValue(empty: true), for: token)
            return try node(style: .flow)
        }
    }

    private mutating func flowMappingValue(empty: Bool) throws -> Event {
        let token = try nextToken()
        switch token.kind {
        case .value where !empty:
            let token = try nextToken()
            switch token.kind {
            case .flowEntry, .flowMappingEnd:
                deferredToken = token
                state = .flowMappingKey(first: false)
                return Event(nullAt: token.start)
            default:
                pushState(.flowMappingKey(first: false), for: token)
                return try node(style: .flow)
            }
        default:
            deferredToken = token
            state = .flowMappingKey(first: false)
            return Event(nullAt: token.start)
        }
    }

}

// MARK: - Constructors

import Foundation

extension YAMLParser {

    /// Creates a parser for decoding a Unicode byte `data`, either by an
    /// explicit `encoding` or by detecting the `encoding`.
    public init(data: Data, encoding: YAMLEncoding? = nil) {
        self.init(reader: AutoContiguousReader.reader(for: data, encoding: encoding))
    }

}
