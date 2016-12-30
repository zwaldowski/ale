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
        cs.insert(charactersIn: "[]%")
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

    static let yamlPlainScalarBreak = CharacterSet(charactersIn: "?:,[]{}")

    static let yamlQuotedScalarBreak: CharacterSet = {
        var cs = CharacterSet.whitespacesAndNewlines
        cs.insert(charactersIn: "'\"")
        return cs
    }()
    
}

struct Scanner {

    private enum State {
        case closed, openKeysAllowed, openKeysDisallowed, finished
    }

    private typealias SimpleKey = (token: Int, isRequired: Bool, Mark)

    private var reader: Reader
    private var buffer = [Token]()
    private var state = State.closed

    private var simpleKeys = [SimpleKey]()
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
            throw ParseError(.invalidEncoding, at: e.mark)
        }

        guard !buffer.isEmpty else {
            throw ParseError(.endOfStream, at: reader.mark)
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

        switch reader.peek {
        case nil: try fetchStreamEnd()
        case "%"? where reader.mark.column == 2: try fetchDirective()
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
        case "'"?: try fetchFlowScalar(style: .singleQuoted)
        case "\""?: try fetchFlowScalar(style: .doubleQuoted)
        case "|"? where flowLevel == 0: try fetchBlockScalar(style: .literal)
        case ">"? where flowLevel == 0: try fetchBlockScalar(style: .folded)
        case "%"?, "@"?, "`"?: throw ParseError(.invalidToken, at: reader.mark)
        case _?: try fetchPlainScalar(prefix: .none, start: nil)
        }
    }

    @discardableResult
    private mutating func fetchMoreTokensIfNeeded(action: () throws -> Bool = { true }) throws -> Bool {
        while try state != .finished && buffer.isEmpty || nextPossibleSimpleKeyAfterRemovingStale() == tokensTaken {
            try fetchNextToken()
            guard try action() else { return false }
        }
        return true
    }

    /// Combines multiple comment lines.
    private mutating func gatherComments() throws {
        var comments = Array<Token.Comment>()
        func popComment() -> Bool {
            guard !buffer.isEmpty else { return false }
            if case .comment(let text) = buffer[0].kind {
                tokensTaken += 1
                comments.append(Token.Comment(text, in: buffer.remove(at: 0).range))
            }
            return true
        }
        
        _ = popComment()
        guard try fetchMoreTokensIfNeeded(action: popComment) else { return }

        if !comments.isEmpty {
            buffer[0].comment.before = Token.Comment(comments.lazy.map { $0.value }.joined(separator: "\n"), in: comments.first!.range.lowerBound ..< comments.last!.range.upperBound)
        }

        if state != .finished && buffer.count < 2 {
            try fetchNextToken()
        }

        if buffer.count > 1, buffer[0].isSingleLine, case .comment(let text) = buffer[1].kind, buffer[0].range.upperBound.line == buffer[1].range.lowerBound.line {
            tokensTaken += 1
            buffer[0].comment.after = Token.Comment(text, in: buffer.remove(at: 1).range)
        }
    }

    private mutating func scanUpToNextToken() throws -> [Token] {
        var tokens = [Token]()
        scanning: while true {
            switch reader.peek {
            case " "?,
                 "\t"? where flowLevel != 0 || state == .openKeysDisallowed:
                try reader.advance()
            case "\n"?, "\r"?:
                try reader.skipLineBreak()

                if flowLevel == 0 {
                    state = .openKeysAllowed
                }
            case "#"?:
                let start = reader.mark
                let text = try reader.scan(untilCharacterFrom: .newlines)
                tokens.append(Token(.comment(text), in: start ..< reader.mark))
            default:
                break scanning
            }
        }
        return tokens
    }

    private enum TagKind {
        case directive, inline
    }

    private enum PlainScalarPrefix: String {
        case none = ""
        case dash = "-"
        case question = "?"
        case colon = ":"
    }

    // MARK: - Fetchers

    private mutating func fetchStreamStart() throws {
        let start = reader.mark
        try reader.advance()

        buffer.append(Token(.streamStart, at: start))
        simpleKeys.append((token: 0, isRequired: false, mark: start))

        state = .openKeysAllowed
    }

    private mutating func fetchStreamEnd() throws {
        // Set the current intendation to -1.
        unrollIndent()

        // Reset simple keys.
        try removePossibleSimpleKey()

        // Write the token.
        buffer.append(Token(.streamEnd, at: reader.mark))

        // The stream is finished.
        state = .finished
    }

    private mutating func fetchDocumentEnd() throws {
        let start = reader.mark
        try reader.advance()

        // Set the current intendation to -1.
        unrollIndent()

        // Reset simple keys. Note that there could not be a block collection
        // after '---'.
        try removePossibleSimpleKey()
        state = .openKeysDisallowed

        guard try reader.skip("."), try reader.skip("."), try reader.peek == nil || reader.skip(characterFrom: .whitespacesAndNewlines) else {
            throw ParseError(.invalidToken, at: reader.mark)
        }

        buffer.append(Token(.documentEnd, in: start ..< reader.mark))
    }

    private mutating func fetchDirective() throws {
        // Set the current intendation to -1.
        unrollIndent()

        // Reset simple keys.
        try removePossibleSimpleKey()
        state = .openKeysDisallowed

        try buffer.append(scanDirective())
    }

    private mutating func fetchFlowStart(for kind: @autoclosure() -> Token.Kind) throws {
        // '[' and '{' may start a simple key.
        try savePossibleSimpleKey()

        // Increase the flow level.
        increaseFlowLevel()

        // Simple keys are allowed after '[' and '{'.
        state = .openKeysAllowed

        // Add FLOW-SEQUENCE-START or FLOW-MAPPING-START.
        let start = reader.mark
        try reader.advance()
        buffer.append(Token(kind(), in: start ..< reader.mark))
    }

    private mutating func fetchFlowEnd(for kind: @autoclosure() -> Token.Kind) throws {
        // Reset possible simple key on the current level.
        try removePossibleSimpleKey()

        // Decrease the flow level.
        decreaseFlowLevel()

        // No simple keys after ']' or '}'.
        state = .openKeysDisallowed

        // Add FLOW-SEQUENCE-END or FLOW-MAPPING-END.
        let start = reader.mark
        try reader.advance()
        buffer.append(Token(kind(), in: start ..< reader.mark))
    }

    private mutating func fetchFlowEntry() throws {
        // Reset possible simple key on the current level.
        try removePossibleSimpleKey()

        // Simple keys are allowed after ','.
        state = .openKeysAllowed

        // Add FLOW-ENTRY.
        let start = reader.mark
        try reader.advance()
        buffer.append(Token(.flowEntry, in: start ..< reader.mark))
    }

    private mutating func fetchBlockEntry() throws {
        let start = reader.mark
        try reader.advance()

        // Second "-"; we may be looking at 2/3 of a DOCUMENT_START
        if try reader.skip("-") {
            // Set the current intendation to -1.
            unrollIndent(at: start)

            // Reset simple keys. Note that there could not be a block collection
            // after '---'.
            try removePossibleSimpleKey()
            state = .openKeysDisallowed

            guard try reader.skip("-") else {
                throw ParseError(.invalidToken, at: start)
            }

            return buffer.append(Token(.documentStart, in: start ..< reader.mark))
        } else if reader.peek != nil && !reader.matches(characterFrom: .whitespacesAndNewlines) {
            // This is a plain SCALAR.
            return try fetchPlainScalar(prefix: .dash, start: start)
        } else if flowLevel == 0 {
            // Block context needs additional checks.
            // Are we allowed to start a new entry?
            guard case .openKeysAllowed = state else {
                throw ParseError(.unexpectedValue, at: reader.mark)
            }

            // We may need to add BLOCK-SEQUENCE-START.
            rollIndent(to: start, for: .blockSequenceStart)
        } else {
            // - * only allowed in block
            throw ParseError(.invalidToken, at: reader.mark)
        }

        // Reset possible simple key on the current level.
        try removePossibleSimpleKey()
        state = .openKeysAllowed

        // Add BLOCK-ENTRY.
        buffer.append(Token(.blockEntry, in: start ..< reader.mark))
    }

    private mutating func fetchKey() throws {
        let start = reader.mark
        try reader.advance()

        // This is actually a plain SCALAR.
        if flowLevel == 0, reader.peek != nil, !reader.matches(characterFrom: .whitespaces) {
            return try fetchPlainScalar(prefix: .question, start: start)
        } else if flowLevel != 0 {
            // Reset possible simple key on the current level.
            try removePossibleSimpleKey()
            state = .openKeysDisallowed
        } else {
            // Block context needs additional checks.
            // Are we allowed to start a key (not nessesary a simple)?
            guard case .openKeysAllowed = state else {
                throw ParseError(.unexpectedKey, at: reader.mark)
            }

            // Simple keys are allowed after '?' in the block context.
            try removePossibleSimpleKey()
            state = .openKeysAllowed

            // We may need to add BLOCK-MAPPING-START.
            rollIndent(to: start, for: .blockMappingStart)
        }

        // Add KEY.
        buffer.append(Token(.key, in: start ..< reader.mark))
    }

    private mutating func fetchValue() throws {
        let start = reader.mark
        try reader.advance()

        // This is actually a plain SCALAR.
        if flowLevel == 0, reader.peek != nil, !reader.matches(characterFrom: .whitespacesAndNewlines) {
            return try fetchPlainScalar(prefix: .colon, start: start)
        } else if let key = simpleKeys.popLast() {
            // Do we determine a simple key?
            // Add KEY.
            buffer.insert(Token(.key, at: key.2), at: key.token - tokensTaken)

            // Add the BLOCK-MAPPING-START token if needed.
            rollIndent(to: key.2, tokenNumber: key.token, for: .blockMappingStart)

            // There cannot be two simple keys one after another.
            state = .openKeysDisallowed
        } else {
            // Block context needs additional checks. (Do they really? They will
            // be caught by the parser anyway.) We are allowed to start a
            // complex value iff we can start a simple key.
            if flowLevel == 0 && state == .openKeysDisallowed {
                throw ParseError(.unexpectedValue, at: reader.mark)
            }

            rollIndent(to: start, for: .blockMappingStart)
            
            // Simple keys are allowed after ':' in the block context.
            state = flowLevel == 0 ? .openKeysAllowed : .openKeysDisallowed
        }

        // Add VALUE.
        buffer.append(Token(.value, in: start ..< reader.mark))
    }

    private mutating func fetchAnchor(kind: (String) -> Token.Kind) throws {
        // ANCHOR could start a simple key.
        try savePossibleSimpleKey()

        // No simple keys after ANCHOR.
        state = .openKeysDisallowed

        // Scan and add ANCHOR.
        try buffer.append(scanAnchor(kind: kind))
    }

    private mutating func fetchTag() throws {
        // TAG could start a simple key.
        try savePossibleSimpleKey()

        // No simple keys after TAG.
        state = .openKeysDisallowed

        // Scan and add TAG.
        try buffer.append(scanTag())
    }

    private mutating func fetchBlockScalar(style: ScalarStyle) throws {
        try savePossibleSimpleKey()

        // A simple key may follow a block scalar.
        state = .openKeysAllowed

        // Scan and add SCALAR.
        try buffer.append(scanBlockScalar(style: style))
    }

    private mutating func fetchFlowScalar(style: ScalarStyle) throws {
        // A flow scalar could be a simple key.
        try savePossibleSimpleKey()

        // No simple keys after flow scalars.
        state = .openKeysDisallowed

        // Scan and add SCALAR.
        try buffer.append(scanFlowScalar(style: style))
    }

    private mutating func fetchPlainScalar(prefix: PlainScalarPrefix, start: Mark?) throws {
        // A plain scalar could be a simple key.
        try savePossibleSimpleKey(at: start)

        // No simple keys after plain scalars, but note that scanPlainScalar
        // may change this flag if the scan is finished at the beginning of
        // the line.
        state = .openKeysDisallowed

        // Scan and add SCALAR.
        try buffer.append(scanPlainScalar(prefix: prefix, start: start ?? reader.mark))
    }

    // MARK: - Simple Keys

    /// The current token may be a potential simple key, so we
    /// need to look further.
    private mutating func nextPossibleSimpleKeyAfterRemovingStale() throws -> Int? {
        try removeStaleSimpleKeys()

        return simpleKeys.min {
            $0.0.token < $0.1.token
        }?.token
    }

    private mutating func removeStaleSimpleKeys() throws {
        for index in simpleKeys.indices.reversed() where simpleKeys[index].2.line < reader.mark.line || reader.mark.offset - simpleKeys[index].2.offset > 1024 {
            if simpleKeys.remove(at: index).isRequired {
                throw ParseError(.expectedKey, at: reader.mark)
            }
        }
    }

    /// The next token may start a simple key. We check if it's possible
    /// and save its position. This function is called for
    ///   ALIAS, ANCHOR, TAG, SCALAR(flow), '[', and '{'.
    private mutating func savePossibleSimpleKey(at mark: Mark? = nil) throws {
        let mark = mark ?? reader.mark

        // Check if a simple key is required at the given position.
        let isRequired = flowLevel == 0 && indent == mark.column

        // The next token might be a simple key...
        guard case .openKeysAllowed = state else { return }

        // Let's save its number and position.
        try removePossibleSimpleKey()
        simpleKeys.append((token: tokensTaken + buffer.count, isRequired: isRequired, mark: mark))
    }

    /// Remove the saved possible key position at the current flow level.
    private mutating func removePossibleSimpleKey() throws {
        guard let key = simpleKeys.popLast() else { return }
        if key.isRequired {
            throw ParseError(.expectedKey, at: reader.mark)
        }
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

    // MARK: -

    private mutating func increaseFlowLevel() {
        simpleKeys.append((token: 0, isRequired: false, mark: Mark(offset: 0, line: 0, column: 0)))
        flowLevel += 1
    }

    private mutating func decreaseFlowLevel() {
        guard flowLevel != 0 else { return }
        flowLevel -= 1
        _ = simpleKeys.popLast()
    }

    // MARK: - Scanners

    private mutating func scanDirective() throws -> Token {
        // See the specification for details.
        let start = reader.mark
        try reader.advance()

        let token: Token
        switch try scanDirectiveName(start: start) {
        case "YAML":
            token = try scanVersionDirectiveValue(start: start)
        case "TAG":
            token = try scanTagDirectiveValue(start: start)
        default:
            try reader.skip(untilCharactersFrom: .newlines)
            token = Token(.tagDirective(handle: "", prefix: ""), in: start ..< reader.mark)
        }

        try reader.skip(charactersFrom: .whitespaces)

        if reader.matches("#") {
            try reader.skip(untilCharactersFrom: .newlines)
        }

        guard try reader.skipLineBreak() else {
            throw ParseError(.expectedWhitespace, at: reader.mark)
        }

        return token
    }

    private mutating func scanDirectiveName(start: Mark) throws -> String {
        let name = try reader.match(charactersFrom: .alphanumerics)
        guard !name.isEmpty else {
            throw ParseError(.directiveFormat, at: reader.mark)
        }

        guard try reader.skip(characterFrom: .whitespaces) else {
            throw ParseError(.directiveFormat, at: reader.mark)
        }

        return name
    }

    private mutating func scanVersionDirectiveValue(start: Mark) throws -> Token {
        try reader.skip(charactersFrom: .whitespaces)

        let major = try scanVersionDirectiveNumber()
        guard try reader.skip(".") else {
            throw ParseError(.directiveFormat, at: reader.mark)
        }
        let minor = try scanVersionDirectiveNumber()

        return Token(.versionDirective(major: major, minor: minor), in: start ..< reader.mark)
    }

    private mutating func scanVersionDirectiveNumber() throws -> Int {
        let string = try reader.match(charactersFrom: .decimalDigits)

        guard let value = Int(string) else {
            throw ParseError(.directiveFormat, at: reader.mark)
        }

        return value
    }

    private mutating func scanTagDirectiveValue(start: Mark) throws -> Token {
        try reader.skip(charactersFrom: .whitespaces)
        let handle = try scanTagHandle(kind: .directive, start: start)

        try reader.skip(charactersFrom: .whitespaces)
        let prefix = try scanTagURI(start: start)

        guard try reader.skip(characterFrom: .whitespacesAndNewlines) else {
            throw ParseError(.directiveFormat, at: reader.mark)
        }

        return Token(.tagDirective(handle: handle, prefix: prefix), in: start ..< reader.mark)
    }

    private mutating func scanTag() throws -> Token {
        let start = reader.mark
        try reader.advance()

        let handle: String
        let suffix: String

        // Eat '!<'
        if try reader.skip("<") {
            suffix = try scanTagURI(start: start)
            handle = ""

            guard try reader.skip(">") else {
                throw ParseError(.tagFormat, at: reader.mark)
            }
        } else {
            // The tag has either the '!suffix' or the '!handle!suffix'
            let tag = try scanTagHandle(kind: .inline, start: start)
            suffix = try scanTagURI(start: start)
            if tag.unicodeScalars.count >= 2 && tag.unicodeScalars.first == "!" && tag.unicodeScalars.last == "!" {
                handle = tag
            } else {
                handle = "!"
            }
        }

        guard reader.matches(characterFrom: .whitespaces) == true else {
            throw ParseError(.tagFormat, at: reader.mark)
        }

        return Token(.tag(handle: handle, suffix: suffix), in: start ..< reader.mark)
    }

    private mutating func scanTagHandle(kind: TagKind, start: Mark) throws -> String {
        guard try reader.skip("!") else {
            throw ParseError(.tagFormat, at: start)
        }

        var string = "!"
        string += try reader.match(charactersFrom: .alphanumerics)

        if try reader.skip("!") {
            string.append("!")
        } else if case .directive = kind, string != "!" {
            // It's either the '!' tag or not really a tag handle. If it's a
            // %TAG directive, that's an error. If it's a tag token, it must be
            // a part of URI.
            throw ParseError(.tagFormat, at: start)
        }

        return string
    }

    private mutating func scanTagURI(start: Mark) throws -> String {
        guard let string = try reader.match(charactersFrom: .yamlURIAllowed).removingPercentEncoding, !string.isEmpty else {
            throw ParseError(.tagFormat, at: start)
        }

        return string
    }

    private mutating func scanAnchor(kind: (String) -> Token.Kind) throws -> Token {
        let start = reader.mark
        try reader.advance()

        let string = try reader.match(charactersFrom: .yamlAnchorAllowed)
        guard !string.isEmpty else {
            throw ParseError(.anchorFormat, at: start)
        }

        return Token(kind(string), in: start ..< reader.mark)
    }

    private mutating func scanBlockScalar(style: ScalarStyle) throws -> Token {
        // skip '|' or '>'
        let start = reader.mark
        try reader.advance()

        // scan indicators
        func parseIncrement(from scalar: UnicodeScalar) -> Int {
            return Int(scalar.value - ("0" as UnicodeScalar).value)
        }

        enum Chomp { case leading, none, trailing }
        let chomping: Chomp
        let increment: Int?

        if try reader.skip("+") {
            chomping = .trailing
            increment = try reader.take(characterFrom: .decimalDigits).map(parseIncrement)
        } else if try reader.skip("-") {
            chomping = .leading
            increment = try reader.take(characterFrom: .decimalDigits).map(parseIncrement)
        } else if let digit = try reader.take(characterFrom: .decimalDigits) {
            increment = parseIncrement(from: digit)

            if try reader.skip("+") {
                chomping = .leading
            } else if try reader.skip("-") {
                chomping = .trailing
            } else {
                chomping = .none
            }
        } else {
            chomping = .none
            increment = nil
        }

        if case 0? = increment {
            throw ParseError(.invalidIndentation, at: reader.mark)
        }

        // Eat whitespaces and comments to the end of the line.
        try reader.skip(charactersFrom: .whitespaces)
        if reader.matches("#") {
            try reader.skip(untilCharactersFrom: .newlines)
        }

        guard try reader.skip(characterFrom: .newlines) else {
            throw ParseError(.expectedWhitespace, at: start)
        }

        // Scan the leading line breaks and determine the indentation level if needed.
        var indent = increment.map { $0 + max(self.indent, 0) } ?? 0
        var leadingBreak = ""
        var trailingBreaks = ""
        var end = try scanBlockScalarBreaks(indent: &indent, into: &trailingBreaks)

        var leadingBlank = false
        var string = ""

        while reader.mark.column == indent {
            // We are at the beginning of a non-empty line.
            if case .folded = style, !leadingBreak.isEmpty, !leadingBlank, !reader.matches(characterFrom: .whitespaces), trailingBreaks.isEmpty {
                string.append(" ")
            } else {
                string.append(leadingBreak)
            }
            leadingBreak.removeAll()

            string.append(trailingBreaks)
            trailingBreaks.removeAll()

            leadingBlank = reader.matches(characterFrom: .whitespaces)
            try string.append(reader.scan(untilCharacterFrom: .newlines))
            if reader.peek == nil { break }

            try leadingBreak.append(reader.scanLineBreak())

            // Eat the following intendation spaces and line breaks.
            end = try scanBlockScalarBreaks(indent: &indent, into: &trailingBreaks)
        }

        let comment: String
        switch chomping {
        case .leading:
            comment = trailingBreaks
        case .none:
            string.append(leadingBreak)
            comment = trailingBreaks
        case .trailing:
            string.append(leadingBreak)
            string.append(trailingBreaks)
            comment = ""
        }

        var token = Token(.scalar(string, style), in: start ..< reader.mark)
        if !comment.isEmpty {
            // Keep track of the trailing whitespace as a comment token, if
            // isn't all included in the actual value.
            token.comment.after = Token.Comment(comment, in: end ..< reader.mark)
        }
        return token
    }

    private mutating func scanBlockScalarBreaks(indent: inout Int, into string: inout String) throws -> Mark {
        var maxIndent = 0
        var end = reader.mark

        while true {
            while indent == 0 || reader.mark.column < indent, reader.matches(" ") {
                try reader.advance()
            }

            maxIndent = max(reader.mark.column, maxIndent)

            // Check for a characters messing the intendation.
            if indent == 0 || reader.mark.column < indent, reader.matches(characterFrom: .whitespaces) {
                throw ParseError(.invalidIndentation, at: reader.mark)
            }

            if !reader.matches(characterFrom: .newlines) { break }

            // Consume the line break.
            try string.append(reader.scanLineBreak())
            end = reader.mark
        }

        if indent == 0 {
            indent = max(max(maxIndent, self.indent + 1), 1)
        }

        return end
    }

    private mutating func scanFlowScalar(style: ScalarStyle) throws -> Token {
        // skip '"'
        let start = reader.mark
        try reader.advance()

        var string = ""
        parsing: while !reader.matches(style == .doubleQuoted ? "\"" : "'") {
            let whitespaces = try reader.match(charactersFrom: .whitespaces)
            if reader.peek == nil {
                throw ParseError(.endOfStream, at: reader.mark)
            } else if reader.matches(characterFrom: .newlines) {
                try string.append(scanScalarBreaks() ?? " ")
            } else {
                string.append(whitespaces)
            }

            try string.append(reader.scan(untilCharacterFrom: .yamlQuotedScalarBreak))
            
            switch (style, reader.peek) {
            case (.singleQuoted, "'"?):
                try reader.advance()
                guard reader.peek == "'" else { break parsing }
                string.unicodeScalars.append("'")
                try reader.advance()
            case (.doubleQuoted, "'"?), (.singleQuoted, "\""?), (.singleQuoted, "\\"?):
                string.unicodeScalars.append(reader.peek!)
                try reader.advance()
            case (.doubleQuoted, "\\"?):
                try reader.advance()
                switch reader.peek {
                case "0"?: string.append("\0")
                case "a"?: string.append("\u{0007}")
                case "b"?: string.append("\u{0008}")
                case "t"?, "\t"?: string.append("\t")
                case "n"?: string.append("\n")
                case "v"?: string.append("\u{000b}")
                case "f"?: string.append("\u{000c}")
                case "r"?: string.append("\r")
                case "e"?: string.append("\u{001b}")
                case " "?: string.append(" ")
                case "\""?: string.append("\"")
                case "/"?: string.append("/")
                case "\\"?: string.append("\\")
                case "N"?: string.append("\u{0085}")
                case "_"?: string.append("\u{00a0}")
                case "L"?: string.append("\u{2028}")
                case "P"?: string.append("\u{2029}")
                case "x"?: try string.unicodeScalars.append(scanEscape(of: UTF8.self))
                case "u"?: try string.unicodeScalars.append(scanEscape(of: UTF16LE.self))
                case "U"?: try string.unicodeScalars.append(scanEscape(of: UTF32LE.self))
                case let newline? where CharacterSet.newlines.contains(newline):
                    try string.append(scanScalarBreaks() ?? " ")
                    continue parsing
                default:
                    throw ParseError(.invalidEscape, at: reader.mark)
                }

                try reader.advance()
            default:
                break
            }
        }

        try reader.advance()

        return Token(.scalar(string, style), in: start ..< reader.mark)
    }

    private mutating func scanEscape<Codec: UnicodeCodec>(of _: Codec.Type) throws -> UnicodeScalar where Codec.CodeUnit: UnsignedInteger {
        try reader.advance()

        var codeUnit = Codec.CodeUnit.allZeros
        for offset in 0 ..< MemoryLayout<Codec.CodeUnit>.size * 2 {
            var byte: Codec.CodeUnit
            switch reader.peek {
            case ("0" ... "9")?:
                byte = numericCast(reader.peek!.value &- ("0" as UnicodeScalar).value)
            case ("A" ... "F")?:
                byte = numericCast(reader.peek!.value &- ("A" as UnicodeScalar).value &+ 10)
            case ("a" ... "f")?:
                byte = numericCast(reader.peek!.value &- ("a" as UnicodeScalar).value &+ 10)
            default:
                throw ParseError(.invalidEscape, at: reader.mark)
            }

            for _ in 0 ..< offset {
                byte = byte &* 256
            }

            codeUnit |= byte

            try reader.advance()
        }

        var codec = Codec()
        var iterator = CollectionOfOne(codeUnit).makeIterator()
        guard case .scalarValue(let scalar) = codec.decode(&iterator) else {
            throw ParseError(.invalidEscape, at: reader.mark)
        }

        return scalar
    }

    private mutating func scanPlainScalar(prefix: PlainScalarPrefix, start: Mark) throws -> Token {
        let indent = self.indent + 1
        var end = start

        var string = prefix.rawValue
        var spaces: String?

        while !reader.matches("#") {
            var chunk = ""

            while let current = reader.peek, !CharacterSet.whitespacesAndNewlines.contains(current) {
                guard flowLevel != 0 || current != ":" else  { break }
                guard flowLevel == 0 || !CharacterSet.yamlPlainScalarBreak.contains(current) else { break }
                chunk.unicodeScalars.append(current)
                try reader.advance()
            }

            guard !chunk.isEmpty else { break }

            if let spaces = spaces {
                string.append(spaces)
            }
            string.append(chunk)

            state = .openKeysDisallowed

            end = reader.mark
            spaces = try scanPlainScalarSpaces(start: start)
            guard spaces != nil, !reader.matches("#"), (flowLevel != 0 || reader.mark.column >= indent) else { break }
        }

        var token = Token(.scalar(string, .plain), in: start ..< end)
        if let spaces = spaces, spaces.unicodeScalars.first == "\n" {
            token.comment.after = Token.Comment("\(spaces)\n", in: end ..< reader.mark)
        }
        return token
    }

    private mutating func scanPlainScalarSpaces(start: Mark) throws -> String? {
        let whitespaces = try reader.match(charactersFrom: .whitespaces)
        if reader.matches(characterFrom: .newlines) {
            guard let lineBreaks = try scanScalarBreaks() else { return nil }
            return lineBreaks.isEmpty ? " " : lineBreaks
        } else if !whitespaces.isEmpty {
            return whitespaces
        } else {
            return nil
        }
    }

    private mutating func scanScalarBreaks() throws -> String? {
        var lineBreaks = try reader.scanLineBreak()
        state = .openKeysAllowed

        enum DocumentIndicator { case start, end }
        var documentIndicator = (kind: DocumentIndicator.start, count: 0)
        func foundDocumentIndicator(_ kind: DocumentIndicator? = nil) -> Bool {
            guard kind == documentIndicator.kind else {
                documentIndicator = (kind ?? .start, 0)
                return false
            }
            documentIndicator.count += 1
            return documentIndicator.count >= 3
        }

        while true {
            if reader.matches("-") && foundDocumentIndicator(.start) {
                return nil
            } else if reader.matches(".") && foundDocumentIndicator(.end) {
                return nil
            } else if try reader.skip(characterFrom: .whitespaces) {
                _ = foundDocumentIndicator(nil)
                continue
            }
            
            let lineBreak = try reader.scanLineBreak()
            if !lineBreak.isEmpty {
                lineBreaks.append(lineBreak)
            } else {
                return lineBreaks
            }
        }
    }

}
