//
//  ScannerTests.swift
//  ale
//
//  Created by Zachary Waldowski on 11/27/16.
//  Copyright © 2016 Zachary Waldowski. All rights reserved.
//

import XCTest

#if SWIFT_PACKAGE
@testable import YAML
#else
@testable import ale
#endif

private protocol ScannerDataTests {
    
    func makeReader(for data: Data) -> YAML.Reader
    var stringEncoding: String.Encoding { get }
    
}

extension ScannerDataTests {
    
    func makeScanner(forBytes bytes: [UInt8]) -> YAML.Scanner {
        let reader = makeReader(for: Data(bytes: bytes))
        return YAML.Scanner(reader: reader)
    }
    
}

private extension Token {

    var hasComments: Bool {
        func isEmptyComment(_ comment: Token.Comment) -> Bool {
            return comment.value.isEmpty || comment.value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) == nil
        }
        
        return comment.before.map(isEmptyComment) == false || comment.after.map(isEmptyComment) == false
    }

}

class ScannerStringTests: XCTestCase {
    
    final func makeScanner(for string: String) -> YAML.Scanner {
        let reader: YAML.Reader
        if let dataScanner = self as? ScannerDataTests {
            let data = string.data(using: dataScanner.stringEncoding)!
            reader = dataScanner.makeReader(for: data)
        } else {
            reader = StringReader(string: string)
        }
        return YAML.Scanner(reader: reader)
    }

    fileprivate func assertNextToken(for scanner: inout YAML.Scanner, is kind: @autoclosure () throws -> Token.Kind, hasComment: @autoclosure() throws -> Bool = false, file: StaticString = #file, line: UInt = #line) {
        do {
            let token = try scanner.next()
            XCTAssertEqual(token.kind, try kind(), file: file, line: line)
            XCTAssert(try token.hasComments == hasComment(), "token did not have expected comments", file: file, line: line)
        } catch {
            XCTFail("unexpected error while parsing token: \(error)", file: file, line: line)
        }
    }
    
    fileprivate func assertError(for scanner: inout YAML.Scanner, file: StaticString = #file, line: UInt = #line, _ errorHandler: (ParseError) -> Void = { _ in }) {
        XCTAssertThrowsError(try scanner.next(), file: file, line: line) { (error) in
            guard let parseError = error as? ParseError else {
                XCTFail("Unexpected error \(error)", file: file, line: line)
                return
            }
            errorHandler(parseError)
        }
    }

    fileprivate func assertEnd(for scanner: inout YAML.Scanner, file: StaticString = #file, line: UInt = #line) {
        assertError(for: &scanner, file: file, line: line) { (error) in
            XCTAssertEqual(error.code, .endOfStream, file: file, line: line)
        }
    }

    func testEmpty() {
        var scan = makeScanner(for: "")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testScalar() {
        var scan = makeScanner(for: "a scalar")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .scalar("a scalar", .plain))
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testExplicitScalar() {
        var scan = makeScanner(for: "---\n'a scalar'\n...\n")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .documentStart)
        assertNextToken(for: &scan, is: .scalar("a scalar", .singleQuoted))
        assertNextToken(for: &scan, is: .documentEnd)
        assertNextToken(for: &scan, is: .streamEnd)
    }

    func testMultipleDocuments() {
        var scan = makeScanner(for: "\n'a scalar'\n---\n'a scalar'\n---\n'a scalar'\n")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .scalar("a scalar", .singleQuoted))
        assertNextToken(for: &scan, is: .documentStart)
        assertNextToken(for: &scan, is: .scalar("a scalar", .singleQuoted))
        assertNextToken(for: &scan, is: .documentStart)
        assertNextToken(for: &scan, is: .scalar("a scalar", .singleQuoted))
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testAFlowSequence() {
        var scan = makeScanner(for: "[item 1, item 2, item 3]")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .flowSequenceStart)
        assertNextToken(for: &scan, is: .scalar("item 1", .plain))
        assertNextToken(for: &scan, is: .flowEntry)
        assertNextToken(for: &scan, is: .scalar("item 2", .plain))
        assertNextToken(for: &scan, is: .flowEntry)
        assertNextToken(for: &scan, is: .scalar("item 3", .plain))
        assertNextToken(for: &scan, is: .flowSequenceEnd)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testAFlowMapping() {
        var scan = makeScanner(for: "\n{\n    a simple key: a value, # Note that the KEY token is produced.\n    ? a complex key: another value,\n}\n")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .flowMappingStart)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("a simple key", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("a value", .plain))
        assertNextToken(for: &scan, is: .flowEntry)
        assertNextToken(for: &scan, is: .key, hasComment: true)
        assertNextToken(for: &scan, is: .scalar("a complex key", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("another value", .plain))
        assertNextToken(for: &scan, is: .flowEntry)
        assertNextToken(for: &scan, is: .flowMappingEnd)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testBlockSequences() {
        var scan = makeScanner(for: "\n- item 1\n- item 2\n-\n  - item 3.1\n  - item 3.2\n-\n  key 1: value 1\n  key 2: value 2\n")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .blockSequenceStart)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 1", .plain))
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 2", .plain))
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .blockSequenceStart)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 3.1", .plain))
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 3.2", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .blockMappingStart)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("key 1", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("value 1", .plain))
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("key 2", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("value 2", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testCommentsBetweenBlockElements() {
        var scan = makeScanner(for: "# c\n- item 1 # d\n# e\n- item 2 # f")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .blockSequenceStart, hasComment: true)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 1", .plain), hasComment: true)
        assertNextToken(for: &scan, is: .blockEntry, hasComment: true)
        assertNextToken(for: &scan, is: .scalar("item 2", .plain), hasComment: true)
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testBlockMappings() {
        var scan = makeScanner(for: "\na simple key: a value   # The KEY token is produced here.\n? a complex key\n: another value\na mapping:\n  key 1: value 1\n  key 2: value 2\na sequence:\n  - item 1\n  - item 2\n")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .blockMappingStart)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("a simple key", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("a value", .plain), hasComment: true)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("a complex key", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("another value", .plain))
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("a mapping", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .blockMappingStart)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("key 1", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("value 1", .plain))
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("key 2", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("value 2", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("a sequence", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .blockSequenceStart)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 1", .plain))
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 2", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testNoBlockSequenceStart() {
        var scan = makeScanner(for: "\nkey:\n- item 1\n- item 2\n")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .blockMappingStart)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("key", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 1", .plain))
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 2", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testCollectionsInSequence() {
        var scan = makeScanner(for: "\n- - item 1\n  - item 2\n- key 1: value 1\n  key 2: value 2\n- ? complex key\n  : complex value\n")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .blockSequenceStart)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .blockSequenceStart)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 1", .plain))
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 2", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .blockMappingStart)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("key 1", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("value 1", .plain))
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("key 2", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("value 2", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .blockMappingStart)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("complex key", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("complex value", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testCollectionsInMapping() {
        var scan = makeScanner(for: "\n? a sequence\n: - item 1\n  - item 2\n? a mapping\n: key 1: value 1\n  key 2: value 2\n")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .blockMappingStart)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("a sequence", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .blockSequenceStart)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 1", .plain))
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("item 2", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("a mapping", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .blockMappingStart)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("key 1", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("value 1", .plain))
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("key 2", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("value 2", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testSpec_EX7_3() {
        var scan = makeScanner(for: "\n{\n    ? foo :,\n    : bar,\n}\n")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .flowMappingStart)
        assertNextToken(for: &scan, is: .key)
        assertNextToken(for: &scan, is: .scalar("foo", .plain))
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .flowEntry)
        assertNextToken(for: &scan, is: .value)
        assertNextToken(for: &scan, is: .scalar("bar", .plain))
        assertNextToken(for: &scan, is: .flowEntry)
        assertNextToken(for: &scan, is: .flowMappingEnd)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }

    func testScanner_CR() {
        var scan = makeScanner(for: "---\r\n- tok1\r\n- tok2")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .documentStart)
        assertNextToken(for: &scan, is: .blockSequenceStart)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("tok1", .plain))
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("tok2", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }
    
    func testThatKeyNotFollowedByWhitespaceIsScalar() {
        var scan = makeScanner(for: "---\n- key :value")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .documentStart)
        assertNextToken(for: &scan, is: .blockSequenceStart)
        assertNextToken(for: &scan, is: .blockEntry)
        assertNextToken(for: &scan, is: .scalar("key", .plain))
        assertNextToken(for: &scan, is: .scalar(":value", .plain))
        assertNextToken(for: &scan, is: .blockEnd)
        assertNextToken(for: &scan, is: .streamEnd)
        assertEnd(for: &scan)
    }
    
    func testThatGarbageAfterDocumentEndIsNotAccepted() {
        var scan = makeScanner(for: "---\n- value\n...foo")
        assertNextToken(for: &scan, is: .streamStart)
        assertNextToken(for: &scan, is: .documentStart)
        assertNextToken(for: &scan, is: .blockSequenceStart)
        assertNextToken(for: &scan, is: .blockEntry)
        assertError(for: &scan) {
            XCTAssertEqual($0.code, .invalidToken)
        }
    }

}

class ScannerUTF8DataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf8
    
    func makeReader(for data: Data) -> YAML.Reader {
        return ContiguousReader<UTF8>(data: data)
    }

    func testInvalidCodeUnit() {
        // "Hello, <<invalid octet>>!"
        var scan = makeScanner(forBytes: [72, 101, 108, 108, 111, 44, 32, 0xf0, 0x28, 0x8c, 0xbc, 33])
        assertError(for: &scan) { (error) in
            XCTAssertEqual(error.code, .invalidEncoding)
        }
    }
    
}

class ScannerUTF16LEDataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf16LittleEndian
    
    func makeReader(for data: Data) -> Reader {
        return ContiguousReader<UTF16LE>(data: data)
    }

}

class ScannerUTF16BEDataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf16BigEndian

    func makeReader(for data: Data) -> Reader {
        return ContiguousReader<UTF16BE>(data: data)
    }

}

class ScannerUTF32LEDataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf32LittleEndian

    func makeReader(for data: Data) -> Reader {
        return ContiguousReader<UTF32LE>(data: data)
    }

}

class ScannerUTF32BEDataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf32BigEndian
    
    func makeReader(for data: Data) -> Reader {
        return ContiguousReader<UTF32BE>(data: data)
    }
    
}

class ScannerAutoUTF8DataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf8
    
    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }

}

class ScannerAutoUTF16DataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf16
    
    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }
    
}

class ScannerAutoUTF16LEDataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf16LittleEndian
    
    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }

}

class ScannerAutoUTF16BEDataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf16BigEndian
    
    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }
    
}

class ScannerAutoUTF32DataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf32
    
    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }
    
}

class ScannerAutoUTF32LEDataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf32LittleEndian
    
    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }

}

class ScannerAutoUTF32BEDataTests: ScannerStringTests, ScannerDataTests {
    
    let stringEncoding = String.Encoding.utf32BigEndian
    
    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }
    
}
