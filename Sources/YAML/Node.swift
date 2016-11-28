//
//  Node.swift
//  ale
//
//  Created by Zachary Waldowski on 11/23/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

/// YAML values can be written in multiple styles for scoping by indentation
/// (block) or denoted by special tokens (flow). Each provides a different
/// trade-off of readability and expression.
public enum ScalarStyle {
    /// Expresses numbers or strings in a flow. Unquoted, and the most readable.
    case plain
    /// Expresses a string in a flow, using `\` escape sequences.
    case doubleQuoted
    /// Expresses a string in a flow, with no escape sequences.
    case singleQuoted
    /// Expresses multi-line text in a block, using a header that describes its
    /// indentation.
    case folded
    /// Expresses multi-line text in a block, taking all indentation as part
    /// of the value.
    case literal
}

/// YAML collections can be scoped by indentation (block) or denoted using
/// special tokens (flow).
public enum CollectionStyle {
    /// A list where each entry is on its own line.
    case block
    /// A comma-separated list.
    case flow
}
