//
//  ScanCommon.swift
//  ale
//
//  Created by Zachary Waldowski on 1/29/17.
//  Copyright © 2017 Zachary Waldowski. All rights reserved.
//

import Foundation

extension Reader {

    mutating func scanLineBreak() throws -> String {
        switch head {
        case "\n"?, "\u{2028}"?, "\u{2029}"?:
            let ret = String(head!)
            try advance()
            return ret
        case "\r"?, "\u{0085}"?:
            try advance()
            try skip("\n")
            return "\n"
        default:
            return ""
        }
    }

    @discardableResult
    mutating func skipLineBreak() throws -> Bool {
        guard matches(characterFrom: .newlines) else { return false }
        if head == "\r" {
            try advance()
            try skip("\n")
        } else {
            try advance()
        }
        return true
    }

    mutating func scanInteger() throws -> Int? {
        return try Int(match(charactersFrom: .decimalDigits))
    }

}

extension Reader {

    private mutating func scanHex() throws -> UInt8 {
        try advance()
        switch head {
        case ("0" ... "9")?:
            return UInt8(head!.value &- ("0" as UnicodeScalar).value)
        case ("A" ... "F")?:
            return UInt8(head!.value &- ("A" as UnicodeScalar).value &+ 10)
        case ("a" ... "f")?:
            return UInt8(head!.value &- ("a" as UnicodeScalar).value &+ 10)
        default:
            throw YAMLParseError(.invalidEscape, at: mark)
        }
    }

    private mutating func scanEscape<Codec: UnicodeCodec>(of _: Codec.Type) throws -> UnicodeScalar where Codec.CodeUnit: UnsignedInteger {
        var codeUnit = Codec.CodeUnit.allZeros

        try withUnsafeMutableBytes(of: &codeUnit) { (ptr) in
            for offset in (0 ..< MemoryLayout<Codec.CodeUnit>.size).reversed() {
                try ptr.storeBytes(of: scanHex() << 4 | scanHex(), toByteOffset: offset, as: UInt8.self)
            }
        }

        var iterator = CollectionOfOne(codeUnit).makeIterator()
        var codec = Codec()

        guard case .scalarValue(let scalar) = codec.decode(&iterator) else {
            throw YAMLParseError(.invalidEscape, at: mark)
        }

        return scalar
    }

    mutating func scanEscape() throws -> UnicodeScalar {
        switch head {
        case "0"?: return "\u{0}"
        case "a"?: return "\u{7}"
        case "b"?: return "\u{8}"
        case "t"?, "\t"?: return "\u{9}"
        case "n"?: return "\u{a}"
        case "v"?: return "\u{b}"
        case "f"?: return "\u{c}"
        case "r"?: return "\u{0d}"
        case "e"?: return "\u{1b}"
        case " "?: return "\u{20}"
        case "\""?: return "\u{22}"
        case "\'"?: return "\u{27}"
        case "\\"?: return "\u{5c}"
        case "/"?: return "\u{2f}"
        case "N"?: return "\u{85}"
        case "_"?: return "\u{a0}"
        case "L"?: return "\u{2028}"
        case "P"?: return "\u{2029}"
        case "x"?: return try scanEscape(of: UTF8.self)
        case "u"?: return try scanEscape(of: UTF16.self)
        case "U"?: return try scanEscape(of: UTF32.self)
        default: throw YAMLParseError(.invalidEscape, at: mark)
        }
    }
    
}
