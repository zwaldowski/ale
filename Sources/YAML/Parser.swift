//
//  Parser.swift
//  ale
//
//  Created by Zachary Waldowski on 12/5/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import Foundation

struct YAMLParser {
    
    private enum State {
        case start
        case documentStart(implicit: Bool)
        case blockNode
        case blockSequenceEntry(first: Bool)
        case indentlessSequenceEntry
        case blockMappingKey(first: Bool)
        case blockMappingValue
        case flowSequenceEntry(first: Bool)
        case flowSequenceEntryMappingKey, flowSequenceEntryMappingValue, flowSequenceEntryMappingEnd
        case flowMappingKey(first: Bool)
        case flowMappingValue(empty: Bool)
        case documentEnd
        case end(mark: Mark)
    }
    
    private var scanner: Scanner
    private var states = [State]()
    private var state = State.start
    private var marks = [Mark]()
    private var token: Token?
    
    mutating func next() throws -> Event {
        switch state {
        case .start: return try parseStreamStart()
        case .documentStart(let implicit): return try parseDocumentStart(implicit: implicit)

        /*
        case blockNode
        case blockSequenceEntry(first: Bool)
        case indentlessSequenceEntry
        case blockMappingKey(first: Bool)
        case blockMappingValue
        case flowSequenceEntry(first: Bool)
        case flowSequenceEntryMappingKey, flowSequenceEntryMappingValue, flowSequenceEntryMappingEnd
        case flowMappingKey(first: Bool)
        case flowMappingValue(empty: Bool)
         */

        case .documentEnd: return try parseDocumentEnd()
        case .end(let mark): throw ParseError(.endOfStream, at: mark)
        default: fatalError()
        }
    }
    
    // MARK: -

    private mutating func nextToken() throws -> Token {
        if let token = token {
            self.token = nil
            return token
        } else {
            return try scanner.next()
        }
    }
    
    private mutating func parseStreamStart() throws -> Event {
        let token = try nextToken()
        guard case .streamStart = token.kind else {
            throw ParseError(.invalidToken, at: token.range.lowerBound)
        }

        state = .documentStart(implicit: true)
        return Event(.streamStart, in: token.range)
    }
    
    private mutating func parseDocumentStart(implicit: Bool) throws -> Event {
        var token = try nextToken()
        if !implicit {
            while case .documentEnd = token.kind {
                token = try nextToken()
            }
        }

        var version = (1, 2)
        var tags = [
            ("!", "!"),
            ("!!", "tag:yaml.org,2002:")
        ]

        switch token.kind {
        case .streamEnd:
            state = .end(mark: token.range.upperBound)
            return Event(.streamEnd, in: token.range)
        case .versionDirective, .tagDirective, .documentStart,
             _ where !implicit:
            let start = token.range.lowerBound

            while true {
                switch token.kind {
                case let .versionDirective(major, minor):
                    guard major == 1 else {
                        throw ParseError(.invalidVersion, at: token.range.lowerBound)
                    }

                    version = (major, minor)
                    token = try nextToken()
                case let .tagDirective(tag):
                    tags.append(tag)
                    token = try nextToken()
                case .documentStart:
                    let end = token.range.upperBound
                    state = .blockNode
                    return Event(.documentStart(version: version, tags: tags), in: start ..< end)
                default:
                    throw ParseError(.invalidToken, at: token.range.lowerBound)
                }
            }
        default:
            self.token = token
            state = .blockNode
            return Event(.documentStart(version: version, tags: tags), at: token.range.lowerBound, isImplicit: true)
        }
    }

    private mutating func parseDocumentEnd() throws -> Event {
        let token = try nextToken()

        switch token.kind {
        case .documentEnd:
            state = .documentStart(implicit: false)
            return Event(.documentEnd, in: token.range)
        default:
            self.token = token
            state = .documentStart(implicit: true)
            return Event(.documentEnd, at: token.range.lowerBound, isImplicit: true)
        }
    }

}
