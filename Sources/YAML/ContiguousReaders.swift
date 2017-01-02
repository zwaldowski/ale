//
//  ContiguousReaders.swift
//  ale
//
//  Created by Zachary Waldowski on 11/23/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import Foundation

/// Supported encodings for YAML.
///
/// - seealso: http://www.unicode.org/versions/Unicode9.0.0/ch03.pdf#G7404
public enum YAMLEncoding {
    /// An 8-bit encoding. A strict superset of ASCII.
    case utf8
    /// A 16-bit encoding delivered in Little Endian byte order.
    case utf16le
    /// A 16-bit encoding delivered in Big Endian byte order.
    case utf16be
    /// A 32-bit encoding delivered in Little Endian byte order.
    case utf32le
    /// A 32-bit encoding delivered in Big Endian byte order.
    case utf32be
}

// MARK: -

private struct ByteIterator<Element: UnsignedInteger>: IteratorProtocol {
    private let data: Data
    private(set) var offset: Data.Index

    init(data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    private typealias Buffer = (
        Element, Element, Element, Element, Element, Element, Element, Element,
        Element, Element, Element, Element, Element, Element, Element, Element
    )
    private var buffer: Buffer = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    public mutating func next() -> Element? {
        guard let nextOffset = data.index(offset, offsetBy: MemoryLayout<Element>.size, limitedBy: data.endIndex) else { return nil }
        defer { offset = nextOffset }
        return withUnsafeMutablePointer(to: &buffer) { (baseAddress) in
            let pointerToElements = UnsafeMutableRawPointer(baseAddress)
            let offsetInBuffer = offset % MemoryLayout<Buffer>.size
            if offsetInBuffer == 0 {
                let upperBound = data.index(offset, offsetBy: MemoryLayout<Buffer>.size, limitedBy: data.endIndex) ?? data.endIndex
                data.copyBytes(to: pointerToElements.assumingMemoryBound(to: UInt8.self), from: offset ..< upperBound)
            }
            return pointerToElements.load(fromByteOffset: offsetInBuffer, as: Element.self)
        }
    }
}

/// A concrete scanner that reads code units of specific type from `Data`.
struct ContiguousReader<Codec: UnicodeCodec>: Reader where Codec.CodeUnit: UnsignedInteger {

    private var iterator: ByteIterator<Codec.CodeUnit>
    private var codec = Codec()

    private var line = 1
    private var column = 0

    private(set) var head: UnicodeScalar?

    /// Creates a scanner for iterating through `data`.
    init(data: Data) {
        iterator = ByteIterator(data: data)
    }

    mutating func advance() throws {
        if matches(characterFrom: .newlines) {
            line += 1
            column = 0
        }

        switch codec.decode(&iterator) {
        case .scalarValue(let scalar):
            head = scalar
            column += 1
        case .emptyInput:
            head = nil
        case .error:
            throw ReadError(code: .invalidCodeUnit, mark: mark)
        }
    }

    var mark: Mark {
        return Mark(offset: iterator.offset, line: line, column: max(column, 1))
    }

}

/// A scanner that guesses the encoding of `Data` using its byte-order mark (if
/// present), then reads code units of that encoding.
struct AutoContiguousReader: Reader {

    private static func detectEncoding(of data: Data) -> (YAMLEncoding, prefix: Int) {
        var prefix: (UInt8, UInt8, UInt8, UInt8) = (.max, .max, .max, .max)
        withUnsafeMutableBytes(of: &prefix) {
            data.copyBytes(to: $0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: data.indices.prefix(4).count)
        }

        switch prefix {
        case (0x00, 0x00, 0xFE, 0xFF):
            return (.utf32be, 4)

        case (0x00, 0x00, 0x00, _):
            return (.utf32be, 0)
        case (0xFF, 0xFE, 0x00, 0x00):
            return (.utf32le, 4)
        case (_, 0x00, 0x00, 0x00):
            return (.utf32le, 0)
        case (0xFE, 0xFF, _, _):
            return (.utf16be, 2)
        case (0x00, _, _, _):
            return (.utf16be, 0)
        case (0xFF, 0xFE, _, _):
            return (.utf16le, 2)
        case (_, 0x00, _, _):
            return (.utf16le, 0)
        case (0xEF, 0xBB, 0xBF, _):
            return (.utf8, 3)
        default:
            return (.utf8, 0)
        }
    }

    private static func reader(for data: Data, encoding: YAMLEncoding) -> Reader {
        switch encoding {
        case .utf8:
            return ContiguousReader<UTF8>(data: data)
        case .utf16le:
            return ContiguousReader<UTF16LE>(data: data)
        case .utf16be:
            return ContiguousReader<UTF16BE>(data: data)
        case .utf32le:
            return ContiguousReader<UTF32LE>(data: data)
        case .utf32be:
            return ContiguousReader<UTF32BE>(data: data)
        }
    }

    private var base: Reader

    /// Creates a scanner for iterating through `data` by guessing its encoding.
    init(data: Data) {
        let (encoding, prefix) = AutoContiguousReader.detectEncoding(of: data)
        let subdata = data.subdata(in: prefix ..< data.endIndex)
        base = AutoContiguousReader.reader(for: subdata, encoding: encoding)
    }

    var head: UnicodeScalar? {
        return base.head
    }

    mutating func advance() throws {
        try base.advance()
    }

    var mark: Mark {
        return base.mark
    }

}

extension AutoContiguousReader {

    /// Creates a scannable suitable for reading a byte stream `data` in a
    /// Unicode `encoding`.
    static func reader(for data: Data, encoding: YAMLEncoding?) -> Reader {
        if let encoding = encoding {
            return reader(for: data, encoding: encoding)
        } else {
            return AutoContiguousReader(data: data)
        }
    }

}
