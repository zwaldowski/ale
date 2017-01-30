//
//  UnicodeExtended.swift
//  ale
//
//  Created by Zachary Waldowski on 11/23/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

private struct UInt16LEIterator<Base: IteratorProtocol>: IteratorProtocol where Base.Element == UInt16 {

    var base: Base
    init(_ base: Base) {
        self.base = base
    }

    mutating func next() -> UInt16? {
        return base.next().map(UInt16.init(littleEndian:))
    }

}

/// A codec for translating between Unicode scalar values and little endian
/// UTF-16 code units, performing byte-swapping if needed.
struct UTF16LE: UnicodeCodec {

    typealias CodeUnit = UTF16.CodeUnit

    private var base = UTF16()

    mutating func decode<I: IteratorProtocol>(_ input: inout I) -> UnicodeDecodingResult where I.Element == UTF16.CodeUnit {
        var overlay = UInt16LEIterator(input)
        defer { input = overlay.base }
        return base.decode(&overlay)
    }

    static func encode(_ input: UnicodeScalar, into processCodeUnit: (UTF16.CodeUnit) -> Void) {
        UTF16.encode(input) {
            processCodeUnit($0.littleEndian)
        }
    }

}

// MARK: -

private struct UInt16BEIterator<Base: IteratorProtocol>: IteratorProtocol where Base.Element == UInt16 {

    var base: Base
    init(_ base: Base) {
        self.base = base
    }

    mutating func next() -> UInt16? {
        return base.next().map(UInt16.init(bigEndian:))
    }

}

/// A codec for translating between Unicode scalar values and big endian
/// UTF-16 code units, performing byte-swapping if needed.
struct UTF16BE: UnicodeCodec {

    typealias CodeUnit = UTF16.CodeUnit

    private var base = UTF16()

    mutating func decode<I: IteratorProtocol>(_ input: inout I) -> UnicodeDecodingResult where I.Element == UTF16.CodeUnit {
        var overlay = UInt16BEIterator(input)
        defer { input = overlay.base }
        return base.decode(&overlay)
    }

    static func encode(_ input: UnicodeScalar, into processCodeUnit: (UTF16.CodeUnit) -> Void) {
        UTF16.encode(input) {
            processCodeUnit($0.bigEndian)
        }
    }

}

// MARK: -

private struct UInt32LEIterator<Base: IteratorProtocol>: IteratorProtocol where Base.Element == UInt32 {

    var base: Base
    init(_ base: Base) {
        self.base = base
    }

    mutating func next() -> UInt32? {
        return base.next().map(UInt32.init(littleEndian:))
    }

}

/// A codec for translating between Unicode scalar values and little endian
/// UTF-32 code units, performing byte-swapping if needed.
struct UTF32LE: UnicodeCodec {

    typealias CodeUnit = UTF32.CodeUnit

    private var base = UTF32()

    mutating func decode<I: IteratorProtocol>(_ input: inout I) -> UnicodeDecodingResult where I.Element == UTF32.CodeUnit {
        var overlay = UInt32LEIterator(input)
        defer { input = overlay.base }
        return base.decode(&overlay)
    }

    static func encode(_ input: UnicodeScalar, into processCodeUnit: (UTF32.CodeUnit) -> Void) {
        UTF32.encode(input) {
            processCodeUnit($0.littleEndian)
        }
    }

}

// MARK: -

private struct UInt32BEIterator<Base: IteratorProtocol>: IteratorProtocol where Base.Element == UInt32 {

    var base: Base
    init(_ base: Base) {
        self.base = base
    }

    mutating func next() -> UInt32? {
        return base.next().map(UInt32.init(bigEndian:))
    }

}
/// A codec for translating between Unicode scalar values and big endian
/// UTF-32 code units, performing byte-swapping if needed.
struct UTF32BE: UnicodeCodec {

    typealias CodeUnit = UTF32.CodeUnit

    private var base = UTF32()

    mutating func decode<I: IteratorProtocol>(_ input: inout I) -> UnicodeDecodingResult where I.Element == UTF32.CodeUnit {
        var overlay = UInt32BEIterator(input)
        defer { input = overlay.base }
        return base.decode(&overlay)
    }

    static func encode(_ input: UnicodeScalar, into processCodeUnit: (UTF32.CodeUnit) -> Void) {
        UTF32.encode(input) {
            processCodeUnit($0.bigEndian)
        }
    }

}
