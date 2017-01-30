//
//  Scanner.swift
//  ale
//
//  Created by Zachary Waldowski on 11/24/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import Foundation

private extension CharacterSet {

    static let yamlURIAllowed: CharacterSet = {
        var cs = CharacterSet.urlFragmentAllowed
        cs.insert(charactersIn: "#%[]")
        return cs
    }()

    static let yamlTagHandleAllowed: CharacterSet = {
        var cs = CharacterSet.urlFragmentAllowed
        cs.insert(charactersIn: "#%")
        cs.remove(charactersIn: "!(),")
        return cs
    }()

    static let yamlAnchorAllowed: CharacterSet = {
        var cs = CharacterSet()
        cs.insert(charactersIn: "\u{21}" ..< "\u{7f}")
        cs.insert("\u{85}")
        cs.insert(charactersIn: "\u{a0}" ..< "\u{d7ff}")
        cs.insert(charactersIn: "\u{e000}" ..< "\u{fffe}")
        cs.insert(charactersIn: "\u{10000}" ..< "\u{10ffff}")
        cs.remove(charactersIn: ",[]{}\u{feff}")
        return cs
    }()

    static let yamlFlowIndicator = CharacterSet(charactersIn: ",[]{}")

}

struct Scanner {

    public typealias Error = YAMLParseError

    private enum State {
        case closed, openKeysAllowed, openKeysDisallowed, finished
    }

    private typealias SimpleKey = AnyMarked<(token: Int, isRequired: Bool)>

    private var reader: Reader
    private var buffer = [Token]()
    private var state = State.closed

    private var simpleKeys = [Int: SimpleKey]()
    private var indent = -1
    private var indents = [Int]()
    private var flowLevel = 0
    private var tokensTaken = 0

    init(reader: Reader) {
        self.reader = reader
    }

    /// Parses to the next element(s) and pops the first one, or `nil` if no
    /// next element exists.
    mutating func next() throws -> Token {
        do {
            try fetchMoreTokensIfNeeded()
            try gatherComments()
        } catch let e as ReadError where e.code == .invalidCodeUnit {
            throw Error(.invalidEncoding, at: e.mark)
        }

        guard !buffer.isEmpty else {
            throw Error(.endOfStream, at: reader.mark)
        }

        tokensTaken += 1
        return buffer.remove(at: 0)
    }

    // MARK: -

    private mutating func fetchNextToken() throws {
        if case .closed = state {
            return try fetchStreamStart()
        }

        // Eat whitespaces and comments until we reach the next token.
        try buffer.append(contentsOf: scanUpToNextToken())

        // Remove obsolete possible simple keys.
        try removeStaleSimpleKeys()

        // Compare the current indentation and column. It may add some tokens
        // and decrease the current indentation level.
        unrollIndent(to: reader.mark.column)

        switch reader.head {
        case nil: try fetchStreamEnd()
        case "%"? where reader.mark.column == 1: try fetchDirective()
        case "-"?: try fetchBlockEntry()
        case "."?: try fetchDocumentEnd()
        case "["?: try fetchFlowStart(for: .flowSequenceStart)
        case "{"?: try fetchFlowStart(for: .flowMappingStart)
        case "]"?: try fetchFlowEnd(for: .flowSequenceEnd)
        case "}"?: try fetchFlowEnd(for: .flowMappingEnd)
        case ","?: try fetchFlowEntry()
        case "?"?: try fetchKey()
        case ":"?: try fetchValue()
        case "*"?: try fetchAnchor(kind: Token.Kind.alias)
        case "&"?: try fetchAnchor(kind: Token.Kind.anchor)
        case "!"?: try fetchTag()
        case "'"?: try fetchSingleQuotedScalar()
        case "\""?: try fetchDoubleQuotedScalar()
        case "|"? where flowLevel == 0, ">"? where flowLevel == 0: try fetchBlockScalar()
        case "%"?, "@"?, "`"?: throw Error(.invalidToken, at: reader.mark)
        case _?: try fetchPlainScalar()
        }
    }

    @discardableResult
    private mutating func fetchMoreTokensIfNeeded(minimum: Int = 1) throws -> Bool {
        var ret = false
        while state != .finished && (buffer.count < minimum || nextPossibleSimpleKey() == tokensTaken) {
            try fetchNextToken()
            ret = true
        }
        return ret || buffer.count >= minimum
    }

    /// Combines multiple comment lines.
    private mutating func gatherComments() throws {
        // Collect the contiguous leading range of comment tokens.
        var nextIndex = buffer.startIndex
        var comments = Array<Token.Comment>()

        while try nextIndex != buffer.endIndex || fetchMoreTokensIfNeeded() {
            let token = buffer[nextIndex]
            guard case .comment(let text) = token.kind else { break }
            tokensTaken += 1
            comments.append(Token.Comment(text, at: token.start))
            buffer.formIndex(after: &nextIndex)
        }

        // Pop the leading comments; set them on the next token.
        buffer.removeSubrange(buffer.startIndex ..< nextIndex)

        if !buffer.isEmpty {
            buffer[0].comment.before = comments.joined()
        }

        // Attempt to pop a trailing comment
        guard try fetchMoreTokensIfNeeded(minimum: 2), buffer[0].isSingleLine,
            case .comment(let text) = buffer[1].kind, buffer[0].start.line == buffer[1].start.line else { return }
        tokensTaken += 1
        buffer[0].comment.after = Token.Comment(text, at: buffer.remove(at: 1).start)
    }

    private mutating func scanUpToNextToken() throws -> [Token] {
        var tokens = [Token]()
        while true {
            // eat whitespace
            while reader.matches(characterFrom: .whitespaces) {
                if flowLevel == 0, reader.matches("\t") {
                    state = .openKeysDisallowed
                }

                try reader.advance()
            }

            // then eat a comment
            if reader.matches("#") {
                let start = reader.mark
                let text = try reader.scan(untilCharacterFrom: .newlines)
                tokens.append(Token(.comment(text), at: start))
            }

            // if it's NOT a line break, then we're done!
            guard try reader.skipLineBreak() else { return tokens }

            // oh yeah, and let's get rid of that simple key
            try removePossibleSimpleKey()

            // new line - we may be able to accept a simple key now
            if flowLevel == 0 {
                state = .openKeysAllowed
            }
        }
    }

    private enum TagKind {
        case directive, inline
    }

    // MARK: - Fetchers

    private mutating func fetchStreamStart() throws {
        let start = reader.mark
        try reader.advance()

        buffer.append(Token(.streamStart, at: start))

        state = .openKeysAllowed
    }

    private mutating func fetchStreamEnd() throws {
        // Set the current intendation to -1.
        unrollIndent()

        // Reset simple keys.
        try removePossibleSimpleKey()
        simpleKeys.removeAll()

        // Write the token.
        buffer.append(Token(.streamEnd, at: reader.mark))

        // The stream is finished.
        state = .finished
    }

    private mutating func fetchDocumentStart(at start: Mark) throws {
        buffer.append(Token(.documentStart, at: start))
    }

    private mutating func fetchDocumentEnd(skipTokens: Bool = true) throws {
        if skipTokens {
            try reader.advance()
        }

        unrollIndent()
        try resetSimpleKeys()

        guard try !skipTokens || (reader.skip(".") && reader.skip(".") && reader.head == nil || reader.skip(characterFrom: .whitespacesAndNewlines)) else {
            throw Error(.invalidToken, at: reader.mark)
        }

        buffer.append(Token(.documentEnd, at: reader.mark))
    }

    private mutating func fetchDirective() throws {
        unrollIndent()
        try resetSimpleKeys()

        // Skip the `%`.
        let start = reader.mark
        try reader.advance()

        switch try scanDirectiveName(start: start) {
        case "YAML":
            try fetchVersionDirective(start: start)
        case "TAG":
            try fetchTagDirective(start: start)
        default:
            try reader.skip(untilCharactersFrom: .newlines)
        }

        try reader.skip(charactersFrom: .whitespaces)

        if reader.matches("#") {
            try reader.skip(untilCharactersFrom: .newlines)
        }

        guard try reader.skipLineBreak() else {
            throw Error(.expectedWhitespace, at: reader.mark)
        }
    }

    private mutating func fetchVersionDirective(start: Mark) throws {
        try reader.skip(charactersFrom: .whitespaces)

        let major = try scanVersion()
        guard try reader.skip(".") else {
            throw Error(.directiveFormat, at: reader.mark)
        }
        let minor = try scanVersion()

        buffer.append(Token(.versionDirective(major: major, minor: minor), at: start))
    }

    private mutating func fetchTagDirective(start: Mark) throws {
        try reader.skip(charactersFrom: .whitespaces)
        try reader.skip("!")
        let handle = try scanTagHandlePrefix(kind: .directive, start: start)

        try reader.skip(charactersFrom: .whitespaces)
        let prefix = try scanTagHandleURI(start: start)

        guard reader.matches(characterFrom: .whitespacesAndNewlines) else {
            throw Error(.directiveFormat, at: reader.mark)
        }

        buffer.append(Token(.tagDirective(handle: handle, prefix: prefix), at: start))
    }

    /// Add FLOW-SEQUENCE-START or FLOW-MAPPING-START.
    private mutating func fetchFlowStart(for kind: @autoclosure() -> Token.Kind) throws {
        try increaseFlowLevel()

        let start = reader.mark
        try reader.advance()
        buffer.append(Token(kind(), at: start))
    }

    /// Add FLOW-SEQUENCE-END or FLOW-MAPPING-END.
    private mutating func fetchFlowEnd(for kind: @autoclosure() -> Token.Kind) throws {
        try decreaseFlowLevel()

        let start = reader.mark
        try reader.advance()
        buffer.append(Token(kind(), at: start))
    }

    private mutating func fetchFlowEntry() throws {
        // Reset possible simple key on the current level.
        try removePossibleSimpleKey()

        // Simple keys are allowed after ','.
        state = .openKeysAllowed

        // Add FLOW-ENTRY.
        let start = reader.mark
        try reader.advance()
        buffer.append(Token(.flowEntry, at: start))
    }

    private mutating func fetchBlockEntry() throws {
        let start = reader.mark
        try reader.advance()

        // Second "-"; we may be looking at 2/3 of a DOCUMENT_START
        if try reader.skip("-") {
            // Set the current intendation to -1.
            unrollIndent(at: start)

            // Note that there cannot be a block collection after '---'.
            try resetSimpleKeys()

            guard try reader.skip("-") else {
                throw Error(.invalidToken, at: reader.mark)
            }

            return buffer.append(Token(.documentStart, at: reader.mark))
        } else if reader.head != nil, !reader.matches(characterFrom: .whitespacesAndNewlines) {
            // This is a plain SCALAR.
            return try fetchPlainScalar(prefix: .negative, start: start)
        } else if flowLevel == 0 {
            // Block context needs additional checks.
            // Are we allowed to start a new entry?
            guard case .openKeysAllowed = state else {
                throw Error(.unexpectedValue, at: reader.mark)
            }

            // We may need to add BLOCK-SEQUENCE-START.
            rollIndent(to: start, for: .blockSequenceStart)
        } else {
            // - * only allowed in block
            throw Error(.invalidToken, at: reader.mark)
        }

        // Reset possible simple key on the current level.
        try removePossibleSimpleKey()
        state = .openKeysAllowed

        // Add BLOCK-ENTRY.
        buffer.append(Token(.blockEntry, at: start))
    }

    private mutating func fetchKey() throws {
        let start = reader.mark
        try reader.advance()

        if !reader.matches(characterFrom: .whitespacesAndNewlines), flowLevel == 0 || (!reader.matches(characterFrom: .yamlFlowIndicator) && buffer.last?.isJSONFlowEnd != true) {
            // This is actually a plain SCALAR.
            return try fetchPlainScalar(prefix: .key, start: start)
        } else if flowLevel != 0 {
            try resetSimpleKeys()
        } else {
            // Block context needs additional checks.
            // Are we allowed to start a key (not nessesary a simple)?
            guard case .openKeysAllowed = state else {
                throw Error(.unexpectedKey, at: reader.mark)
            }

            // Simple keys are allowed after '?' in the block context.
            try removePossibleSimpleKey()
            state = .openKeysAllowed

            // We may need to add BLOCK-MAPPING-START.
            rollIndent(to: start, for: .blockMappingStart)
        }

        // Add KEY.
        buffer.append(Token(.key, at: start))
    }

    private mutating func fetchValue(skipToken: Bool = true) throws {
        let start = reader.mark
        if skipToken {
            try reader.advance()
        }

        if !reader.matches(characterFrom: .whitespacesAndNewlines), flowLevel == 0 || (!reader.matches(characterFrom: .yamlFlowIndicator) && buffer.last?.isJSONFlowEnd != true) {
            // This is actually a plain SCALAR.
            return try fetchPlainScalar(prefix: .value, start: start)
        } else if let key = simpleKeys.removeValue(forKey: flowLevel) {
            // Do we determine a simple key?
            // Add KEY.
            buffer.insert(Token(.key, at: key.start), at: key.content.token - tokensTaken)

            // Add the BLOCK-MAPPING-START token if needed.
            rollIndent(to: key.start, tokenNumber: key.content.token, for: .blockMappingStart)

            // There cannot be two simple keys one after another.
            state = .openKeysDisallowed
        } else {
            // Block context needs additional checks. (Do they really? They will
            // be caught by the parser anyway.) We are allowed to start a
            // complex value iff we can start a simple key.
            if flowLevel == 0 && state == .openKeysDisallowed {
                throw Error(.unexpectedValue, at: reader.mark)
            }

            rollIndent(to: start, for: .blockMappingStart)

            // Simple keys are allowed after ':' in the block context.
            state = flowLevel == 0 ? .openKeysAllowed : .openKeysDisallowed
        }

        // Add VALUE.
        buffer.append(Token(.value, at: start))
    }

    private mutating func fetchAnchor(kind: (String) -> Token.Kind) throws {
        // ANCHOR could start a simple key, but not after.
        try savePossibleSimpleKey()
        state = .openKeysDisallowed

        // Skip `&` or `*`.
        let start = reader.mark
        try reader.advance()

        let string = try reader.match(charactersFrom: .yamlAnchorAllowed)
        guard !string.isEmpty else {
            throw Error(.anchorFormat, at: start)
        }

        buffer.append(Token(kind(string), at: start))
    }

    private mutating func fetchTag() throws {
        // ANCHOR could start a simple key, but not after.
        try savePossibleSimpleKey()
        state = .openKeysDisallowed

        // Skip past '!'.
        let start = reader.mark
        try reader.advance()

        let handle: String
        let suffix: String

        // Eat '!<'
        if try reader.skip("<") {
            handle = ""
            suffix = try scanTagHandleURI(start: start)

            guard try reader.skip(">") else {
                throw Error(.tagFormat, at: reader.mark)
            }
        } else {
            // The tag has either the '!suffix' or the '!handle!suffix' form.
            let prefix = try scanTagHandlePrefix(kind: .inline, start: start)
            if prefix.unicodeScalars.count > 1 && prefix.unicodeScalars.first == "!" && prefix.unicodeScalars.last == "!" {
                handle = prefix
                suffix = try scanTagHandleSuffix(start: start)
                guard !suffix.isEmpty else {
                    throw Error(.tagFormat, at: reader.mark)
                }
            } else {
                let uri = try scanTagHandleSuffix(start: start)

                if !prefix.isEmpty {
                    handle = "!"
                    suffix = "\(prefix.unicodeScalars.dropFirst())\(uri)"
                } else if !uri.isEmpty {
                    handle = "!"
                    suffix = uri
                } else {
                    handle = ""
                    suffix = "!"
                }
            }
        }

        buffer.append(Token(.tag(handle: handle, suffix: suffix), at: start))
    }

    private mutating func fetchBlockScalar() throws {
        // A simple key may follow a block scalar.
        try savePossibleSimpleKey()
        defer { state = .openKeysAllowed }

        // Scan and add SCALAR.
        // skip '|' or '>'
        let start = reader.mark
        let isFolded = reader.head == ">"
        try reader.advance()

        var subscanner = try BlockScalarScanner(folded: isFolded, headerFrom: &reader, currentIndent: indents.last)

        try buffer.append(subscanner.scan(from: &reader, at: start))
    }

    private mutating func fetchSingleQuotedScalar() throws {
        // A flow scalar could be a simple key, but not after flow scalars.
        try savePossibleSimpleKey()
        defer { state = .openKeysDisallowed }

        // Scan and add SCALAR.
        // skip '"'
        let start = reader.mark
        try reader.advance()

        var subscanner = SingleQuotedScalarScanner()

        try buffer.append(subscanner.scan(from: &reader, at: start))
    }

    private mutating func fetchDoubleQuotedScalar() throws {
        // A flow scalar could be a simple key, but not after flow scalars.
        try savePossibleSimpleKey()
        defer { state = .openKeysDisallowed }

        // Scan and add SCALAR.
        // skip "\""
        let start = reader.mark
        try reader.advance()

        var subscanner = DoubleQuotedScalarScanner()

        try buffer.append(subscanner.scan(from: &reader, at: start))
    }

    private mutating func fetchPlainScalar(prefix: PlainScalarScanner.Prefix? = nil, start: Mark? = nil) throws {
        // A plain scalar could be a simple key, but not after.
        try savePossibleSimpleKey(at: start)
        state = .openKeysDisallowed

        var subscanner = PlainScalarScanner(prefix: prefix, indent: indent, flowLevel: flowLevel)

        try buffer.append(subscanner.scan(from: &reader, at: start ?? reader.mark))

        state = subscanner.hasLeadingSpaces ? .openKeysAllowed : .openKeysDisallowed

        switch subscanner.needsDocument {
        case .confirmed(.start):
            try fetchDocumentEnd(skipTokens: false)

            buffer.append(Token(.documentStart, at: reader.mark))
        case .confirmed(.end):
            try fetchDocumentEnd(skipTokens: false)
        case .none, .possible:
            break
        }

        switch subscanner.needsValue {
        case .confirmed:
            try fetchValue(skipToken: false)
        case .none, .possible:
            break
        }
    }

    // MARK: - Simple Keys

    /// The current token may be a potential simple key, so we
    /// need to look further.
    private func nextPossibleSimpleKey() -> Int? {
        return simpleKeys.values.map { $0.content.token }.min()
    }

    private mutating func removeStaleSimpleKeys() throws {
        for (flowLevel, key) in simpleKeys where key.start.line < reader.mark.line || reader.mark.offset - key.start.offset > 1024 {
            guard !key.content.isRequired else {
                throw Error(.expectedKey, at: reader.mark)
            }

            simpleKeys.removeValue(forKey: flowLevel)
        }
    }

    /// The next token may start a simple key. We check if it's possible
    /// and save its position. This function is called for
    ///   ALIAS, ANCHOR, TAG, SCALAR(flow), '[', and '{'.
    private mutating func savePossibleSimpleKey(at mark: Mark? = nil) throws {
        let mark = mark ?? reader.mark

        // The next token might be a simple key...
        guard case .openKeysAllowed = state else { return }

        // Check if a simple key is required at the given position.
        let isRequired = flowLevel == 0 && indent == mark.column

        // Let's save its number and position.
        try removePossibleSimpleKey()
        simpleKeys[flowLevel] = AnyMarked((token: tokensTaken + buffer.count, isRequired: isRequired), at: mark)
    }

    /// Remove the saved possible key position at the current flow level.
    private mutating func removePossibleSimpleKey() throws {
        guard let key = simpleKeys.removeValue(forKey: flowLevel) else { return }

        if key.content.isRequired {
            throw Error(.expectedKey, at: reader.mark)
        }
    }

    /// Resets possible simple key on the current flow level.
    private mutating func resetSimpleKeys() throws {
        try removePossibleSimpleKey()
        state = .openKeysDisallowed
    }

    // MARK: - Indentation

    /// Check if we need to increase indentation.
    private mutating func rollIndent(to mark: Mark, tokenNumber: Int? = nil, for kind: @autoclosure() -> Token.Kind) {
        guard flowLevel == 0, indent < mark.column else { return }
        indents.append(indent)
        indent = mark.column

        let token = Token(kind(), at: mark)
        if let tokenNumber = tokenNumber {
            buffer.insert(token, at: tokenNumber - tokensTaken)
        } else {
            buffer.append(token)
        }
    }

    /// In flow context, tokens should respect indentation.
    /// Actually the condition should be `self.indent >= column` according to
    /// the spec. But this condition will prohibit intuitively correct
    /// constructions such as:
    ///
    ///     key : {
    ///     }
    ///
    private mutating func unrollIndent(to indent: Int = -1, at mark: Mark? = nil) {
        // In the flow context, indentation is ignored. We make the scanner less
        // restrictive then specification requires.
        guard flowLevel == 0 else { return }

        // In block context, we may need to issue the BLOCK-END tokens.
        while self.indent > indent {
            buffer.append(Token(.blockEnd, at: mark ?? reader.mark))
            self.indent = indents.popLast() ?? -1
        }
    }

    private mutating func increaseFlowLevel() throws {
        // '[' and '{' may start a simple key.
        try savePossibleSimpleKey()

        // Increase the flow level.
        flowLevel += 1

        // Simple keys are allowed after '[' and '{'.
        state = .openKeysAllowed
    }

    private mutating func decreaseFlowLevel() throws {
        try resetSimpleKeys()

        if flowLevel != 0 {
            flowLevel -= 1
        }
    }

    // MARK: - Utilities

    private mutating func scanDirectiveName(start: Mark) throws -> String {
        let name = try reader.match(charactersFrom: .alphanumerics)
        guard !name.isEmpty else {
            throw Error(.directiveFormat, at: reader.mark)
        }

        guard try reader.skip(characterFrom: .whitespaces) else {
            throw Error(.directiveFormat, at: reader.mark)
        }

        return name
    }

    private mutating func scanVersion() throws -> Int {
        guard let value = try reader.scanInteger() else {
            throw Error(.directiveFormat, at: reader.mark)
        }

        return value
    }

    private mutating func scanTagHandlePrefix(kind: TagKind, start: Mark) throws -> String {
        var string = "!"
        string += try reader.match(charactersFrom: .alphanumerics)

        if try reader.skip("!") {
            string.append("!")
        } else if case .directive = kind, string != "!" {
            // It's either the '!' tag or not really a tag handle. If it's a
            // %TAG directive, that's an error. If it's a tag token, it must be
            // a part of URI.
            throw Error(.tagFormat, at: start)
        }

        return string
    }

    private mutating func scanTagHandleURI(start: Mark) throws -> String {
        guard let uri = try reader.match(charactersFrom: .yamlURIAllowed).removingPercentEncoding else {
            throw Error(.tagFormat, at: start)
        }

        return uri
    }

    private mutating func scanTagHandleSuffix(start: Mark) throws -> String {
        guard let uri = try reader.match(charactersFrom: .yamlTagHandleAllowed).removingPercentEncoding else {
            throw Error(.tagFormat, at: start)
        }

        return uri
    }

}
