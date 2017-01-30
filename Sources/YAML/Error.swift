//
//  Error.swift
//  ale
//
//  Created by Zachary Waldowski on 11/29/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

/// Errors that arise from parsing a YAML stream.
public struct YAMLParseError: Swift.Error {
    /// Kinds of error that may arise.
    ///
    /// - see: YAMLParseError
    public enum Code {
        case endOfStream
        case invalidEncoding, invalidVersion, invalidToken, invalidIndentation, invalidEscape
        case expectedKey, expectedValue, expectedWhitespace
        case unexpectedKey, unexpectedValue, unexpectedDirective
        case directiveFormat, tagFormat, anchorFormat
    }

    /// The kind of error that arose.
    public let code: Code

    /// The location in the stream at which the error arose.
    public let mark: Mark

    init(_ code: Code, at mark: Mark) {
        self.code = code
        self.mark = mark
    }

    /// While reading a token, found unexpected end of stream.
    public static var endOfStream: Code { return .endOfStream }

    // MARK: - Invalid tokens

    /// While reading characters, found an invalid sequence of bytes.
    ///
    /// YAML documents are encoded only in Unicode.
    public static var invalidEncoding: Code { return .invalidEncoding }

    /// While parsing directives, found an invalid YAML version.
    ///
    /// This module only supports YAML 1.x streams.
    public static var invalidVersion: Code { return .invalidVersion }

    /// While reading a token, found an unexpected starting character.
    public static var invalidToken: Code { return .invalidToken }

    /// While reading a block, found either no or inconsistent indentation.
    public static var invalidIndentation: Code { return .invalidIndentation }

    /// While reading a literal, found badly-formed Unicode escape.
    ///
    /// All non-printable or unencodable characters must be represented as
    /// a backslash-escaped character or sequence of hex bytes representing
    /// a Unicode scalar.
    public static var invalidEscape: Code { return .invalidEscape }

    // MARK: - Expected tokens

    /// While reading a map, expected a key.
    ///
    /// A simple key (a scalar on a single line) must be terminated by `:`.
    /// A complex key must begin with `?` and be terminated by `:`.
    public static var expectedKey: Code { return .expectedKey }

    /// While reading a sequence, expected an element.
    ///
    /// A sequence must be separated by `,` and terminated by `]`. 
    public static var expectedValue: Code { return .expectedValue }

    /// While reading a line, found unexpected characters.
    ///
    /// A directive or each line of a block scalar must be terminated by
    /// a comment or a line break.
    public static var expectedWhitespace: Code { return .expectedWhitespace }

    // MARK: - Unexpected tokens

    /// Mapping keys are not allowed in this context.
    public static var unexpectedKey: Code { return .unexpectedKey }

    /// Block sequence entries or mapping values are not allowed in this
    /// context.
    public static var unexpectedValue: Code { return .unexpectedValue }

    /// Duplicate YAML or TAG directives are not allowed.
    public static var unexpectedDirective: Code { return .unexpectedDirective }

    // MARK: - Formatting errors

    /// While reading a directive, did not find the expected format.
    ///
    /// A directive is a frontmatter instruction beginning with `%` that
    /// affects the parser itself.
    public static var directiveFormat: Code { return .directiveFormat }

    /// While reading a tag, did not find the expected format.
    ///
    /// Tags are denoted using a `!` and a URI. These global tags may be
    /// nicknamed using a `TAG` directive. Application-specific local tags
    /// may also be used.
    public static var tagFormat: Code { return .tagFormat }

    /// While reading an anchor or alias, found unexpected characters.
    ///
    /// Anchors and aliases use identifiers of alphanumeric characters.
    public static var anchorFormat: Code { return .anchorFormat }

}

extension YAMLParseError.Code {

    /// Pattern matching operator, i.e., `catch Scanner.Error.endOfStream`.
    public static func ~=(match: YAMLParseError.Code, error: Error) -> Bool {
        return match == (error as? YAMLParseError)?.code
    }

}
