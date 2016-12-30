//
//  Event.swift
//  ale
//
//  Created by Zachary Waldowski on 11/23/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

struct Event {

    enum Kind {
        case streamStart
        case streamEnd
        case documentStart(version: (Int, Int), tags: [(String, String)])
        case documentEnd
        case alias(anchor: String)
        case scalar(anchor: String, tag: String, content: String, style: ScalarStyle)
        case sequenceStart(anchor: String, tag: String, style: CollectionStyle)
        case sequenceEnd
        case mappingStart(anchor: String, tag: String, style: CollectionStyle)
        case mappingEnd
    }

    let kind: Kind
    let range: Range<Mark>
    let isImplicit: Bool
    var comments = [String]()

    init(_ kind: Kind, at start: Mark, isImplicit: Bool = false) {
        self.kind = kind
        self.range = start ..< start
        self.isImplicit = isImplicit
    }

    init(_ kind: Kind, in range: Range<Mark>, isImplicit: Bool = false) {
        self.kind = kind
        self.range = range
        self.isImplicit = isImplicit
    }

}
