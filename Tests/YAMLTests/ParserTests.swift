//
//  ParserTests.swift
//  ale
//
//  Created by Zachary Waldowski on 1/2/17.
//  Copyright © 2017 Zachary Waldowski. All rights reserved.
//

import XCTest

#if SWIFT_PACKAGE
@testable import YAML
#else
@testable import ale
#endif

private protocol ParserDataTests {

    func makeReader(for data: Data) -> YAML.Reader
    var stringEncoding: String.Encoding { get }

}

class ParserStringTests: XCTestCase {

    override func setUp() {
        super.setUp()

        continueAfterFailure = false
    }

    final func makeParser(for string: String) -> YAMLParser {
        let reader: YAML.Reader
        if let dataScanner = self as? ParserDataTests {
            let data = string.data(using: dataScanner.stringEncoding)!
            reader = dataScanner.makeReader(for: data)
        } else {
            reader = StringReader(string: string)
        }
        return YAMLParser(reader: reader)
    }

    private enum Event: Equatable {
        case documentStart
        case _sequenceStart(style: YAMLCollectionStyle, tag: String)
        case sequenceEnd
        case _mappingStart(style: YAMLCollectionStyle, tag: String)
        case mappingEnd
        case emptyScalar
        case _scalar(content: String, tag: String)
        case alias
        case documentEnd

        static func scalar(_ content: String, tag: String = "") -> Event {
            return ._scalar(content: content, tag: tag)
        }

        static func sequenceStart(style: YAMLCollectionStyle, tag: String = "") -> Event {
            return ._sequenceStart(style: style, tag: tag)
        }

        static func mappingStart(style: YAMLCollectionStyle, tag: String = "") -> Event {
            return ._mappingStart(style: style, tag: tag)
        }

        init(_ other: YAMLParser.Event.Kind) {
            switch other {
            case .documentStart:
                self = .documentStart
            case let .sequenceStart(_, tag, style):
                self = ._sequenceStart(style: style, tag: tag)
            case .sequenceEnd:
                self = .sequenceEnd
            case let .mappingStart(_, tag, style):
                self = ._mappingStart(style: style, tag: tag)
            case .mappingEnd:
                self = .mappingEnd
            case .scalar(_, "", "", .plain):
                self = .emptyScalar
            case let .scalar(_, tag, content, _):
                self = ._scalar(content: content, tag: tag)
            case .alias:
                self = .alias
            case .documentEnd:
                self = .documentEnd
            }
        }

        static func == (lhs: Event, rhs: Event) -> Bool {
            switch (lhs, rhs) {
            case (.documentStart, .documentStart), (.sequenceEnd, .sequenceEnd), (.mappingEnd, .mappingEnd), (.emptyScalar, .emptyScalar), (.alias, .alias), (.documentEnd, .documentEnd):
                return true
            case let (._sequenceStart(lhs), ._sequenceStart(rhs)):
                return lhs == rhs
            case let (._mappingStart(lhs), ._mappingStart(rhs)):
                return lhs == rhs
            case let (._scalar(lhs), ._scalar(rhs)):
                return lhs == rhs
            default:
                return false
            }
        }

    }

    private func assertNextEvent(for parser: inout YAMLParser, is kind: @autoclosure() -> Event, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(try Event(parser.next().kind), kind(), file: file, line: line)
    }

    private func assertError(fromConsuming parser: inout YAMLParser, file: StaticString = #file, line: UInt = #line, _ errorHandler: (YAMLParser.Error) -> Void = { _ in }) {
        while true {
            do {
                _ = try parser.next()
            } catch YAMLParser.Error.endOfStream {
                XCTFail("Unexpected end of stream", file: file, line: line)
                return
            } catch let error as YAMLParser.Error {
                errorHandler(error)
                return
            } catch {
                XCTFail("Unexpected error \(error)", file: file, line: line)
                return
            }
        }
    }

    // MARK: - Preview

    private let example_2_1 = "- Mark McGwire\n- Sammy Sosa\n- Ken Griffey"
    private let example_2_2 = "hr:  65    # Home runs\navg: 0.278 # Batting average\nrbi: 147   # Runs Batted In"
    private let example_2_3 = "american:\n- Boston Red Sox\n- Detroit Tigers\n- New York Yankees\nnational:\n- New York Mets\n- Chicago Cubs\n- Atlanta Braves"
    private let example_2_4 = "-\n  name: Mark McGwire\n  hr:   65\n  avg:  0.278\n-\n  name: Sammy Sosa\n  hr:   63\n  avg:  0.288"
    private let example_2_5 = "- [name        , hr, avg  ]\n- [Mark McGwire, 65, 0.278]\n- [Sammy Sosa  , 63, 0.288]"
    private let example_2_6 = "Mark McGwire: {hr: 65, avg: 0.278}\nSammy Sosa: {\n    hr: 63,\n    avg: 0.288\n  }"
    private let example_2_7 = "# Ranking of 1998 home runs\n---\n- Mark McGwire\n- Sammy Sosa\n- Ken Griffey\n\n# Team ranking\n---\n- Chicago Cubs\n- St Louis Cardinals"
    private let example_2_8 = "---\ntime: 20:03:20\nplayer: Sammy Sosa\naction: strike (miss)\n...\n---\ntime: 20:03:47\nplayer: Sammy Sosa\naction: grand slam\n..."
    private let example_2_9 = "---\nhr: # 1998 hr ranking\n  - Mark McGwire\n  - Sammy Sosa\nrbi:\n  # 1998 rbi ranking\n  - Sammy Sosa\n  - Ken Griffey"
    private let example_2_10 = "---\nhr:\n  - Mark McGwire\n  # Following node labeled SS\n  - &SS Sammy Sosa\nrbi:\n  - *SS # Subsequent occurrence\n  - Ken Griffey"
    private let example_2_11 = "? - Detroit Tigers\n  - Chicago cubs\n:\n  - 2001-07-23\n\n? [ New York Yankees,\n    Atlanta Braves ]\n: [ 2001-07-02, 2001-08-12,\n    2001-08-14 ]"
    private let example_2_12 = "---\n# Products purchased\n- item    : Super Hoop\n  quantity: 1\n- item    : Basketball\n  quantity: 4\n- item    : Big Shoes\n  quantity: 1"
    private let example_2_13 = "# ASCII Art\n--- |\n  \\//||\\/||\n  // ||  ||__"
    private let example_2_14 = "--- >\n  Mark McGwire's\n  year was crippled\n  by a knee injury."
    private let example_2_15 = ">\n Sammy Sosa completed another\n fine season with great stats.\n \n   63 Home Runs\n   0.288 Batting Average\n \n What a year!"
    private let example_2_16 = "name: Mark McGwire\naccomplishment: >\n  Mark set a major league\n  home run record in 1998.\nstats: |\n  65 Home Runs\n  0.278 Batting Average\n"
    private let example_2_17 = "unicode: \"Sosa did fine.\\u263A\"\ncontrol: \"\\b1998\\t1999\\t2000\\n\"\nhex esc: \"\\x0d\\x0a is \\r\\n\"\n\nsingle: '\"Howdy!\" he cried.'\nquoted: ' # Not a ''comment''.'\ntie-fighter: '|\\-*-/|'"
    private let example_2_18 = "plain:\n  This unquoted scalar\n  spans many lines.\n\nquoted: \"So does this\n  quoted scalar.\\n\""
    private let example_2_23 = "---\nnot-date: !!str 2002-04-28\n\npicture: !!binary |\n R0lGODlhDAAMAIQAAP//9/X\n 17unp5WZmZgAAAOfn515eXv\n Pz7Y6OjuDg4J+fn5OTk6enp\n 56enmleECcgggoBADs=\n\napplication specific tag: !something |\n The semantics of the tag\n above may be different for\n different documents."
    private let example_2_24 = "%TAG ! tag:clarkevans.com,2002:\n--- !shape\n  # Use the ! handle for presenting\n  # tag:clarkevans.com,2002:circle\n- !circle\n  center: &ORIGIN {x: 73, y: 129}\n  radius: 7\n- !line\n  start: *ORIGIN\n  finish: { x: 89, y: 102 }\n- !label\n  start: *ORIGIN\n  color: 0xFFEEBB\n  text: Pretty vector drawing."
    private let example_2_25 = "# Sets are represented as a\n# Mapping where each key is\n# associated with a null value\n--- !!set\n? Mark McGwire\n? Sammy Sosa\n? Ken Griffey"
    private let example_2_26 = "# Ordered maps are represented as\n# A sequence of mappings, with\n# each mapping having one key\n--- !!omap\n- Mark McGwire: 65\n- Sammy Sosa: 63\n- Ken Griffey: 58"
    private let example_2_27 = "--- !<tag:clarkevans.com,2002:invoice>\ninvoice: 34843\ndate   : 2001-01-23\nbill-to: &id001\n    given  : Chris\n    family : Dumars\n    address:\n        lines: |\n            458 Walkman Dr.\n            Suite #292\n        city    : Royal Oak\n        state   : MI\n        postal  : 48046\nship-to: *id001\nproduct:\n    - sku         : BL394D\n      quantity    : 4\n      description : Basketball\n      price       : 450.00\n    - sku         : BL4438H\n      quantity    : 1\n      description : Super Hoop\n      price       : 2392.00\ntax  : 251.42\ntotal: 4443.52\ncomments:\n    Late afternoon is best.\n    Backup contact is Nancy\n    Billsmer @ 338-4338."
    private let example_2_28 = "---\nTime: 2001-11-23 15:01:42 -5\nUser: ed\nWarning:\n  This is an error message\n  for the log file\n---\nTime: 2001-11-23 15:02:31 -5\nUser: ed\nWarning:\n  A slightly different error\n  message.\n---\nDate: 2001-11-23 15:03:17 -5\nUser: ed\nFatal:\n  Unknown variable \"bar\"\nStack:\n  - file: TopClass.py\n    line: 23\n    code: |\n      x = MoreObject(\"345\\n\")\n  - file: MoreClass.py\n    line: 58\n    code: |-\n      foo = bar"

    func testExample_2_1_SeqScalars() {
        var parser = makeParser(for: example_2_1)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Mark McGwire"))
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .scalar("Ken Griffey"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_2_MappingScalarsToScalars() {
        var parser = makeParser(for: example_2_2)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("hr"))
        assertNextEvent(for: &parser, is: .scalar("65"))
        assertNextEvent(for: &parser, is: .scalar("avg"))
        assertNextEvent(for: &parser, is: .scalar("0.278"))
        assertNextEvent(for: &parser, is: .scalar("rbi"))
        assertNextEvent(for: &parser, is: .scalar("147"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_3_MappingScalarsToSequences() {
        var parser = makeParser(for: example_2_3)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("american"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Boston Red Sox"))
        assertNextEvent(for: &parser, is: .scalar("Detroit Tigers"))
        assertNextEvent(for: &parser, is: .scalar("New York Yankees"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .scalar("national"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("New York Mets"))
        assertNextEvent(for: &parser, is: .scalar("Chicago Cubs"))
        assertNextEvent(for: &parser, is: .scalar("Atlanta Braves"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_4_SequenceOfMappings() {
        var parser = makeParser(for: example_2_4)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("name"))
        assertNextEvent(for: &parser, is: .scalar("Mark McGwire"))
        assertNextEvent(for: &parser, is: .scalar("hr"))
        assertNextEvent(for: &parser, is: .scalar("65"))
        assertNextEvent(for: &parser, is: .scalar("avg"))
        assertNextEvent(for: &parser, is: .scalar("0.278"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("name"))
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .scalar("hr"))
        assertNextEvent(for: &parser, is: .scalar("63"))
        assertNextEvent(for: &parser, is: .scalar("avg"))
        assertNextEvent(for: &parser, is: .scalar("0.288"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_5_SequenceOfSequences() {
        var parser = makeParser(for: example_2_5)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("name"))
        assertNextEvent(for: &parser, is: .scalar("hr"))
        assertNextEvent(for: &parser, is: .scalar("avg"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("Mark McGwire"))
        assertNextEvent(for: &parser, is: .scalar("65"))
        assertNextEvent(for: &parser, is: .scalar("0.278"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .scalar("63"))
        assertNextEvent(for: &parser, is: .scalar("0.288"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_6_MappingOfMappings() {
        var parser = makeParser(for: example_2_6)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Mark McGwire"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("hr"))
        assertNextEvent(for: &parser, is: .scalar("65"))
        assertNextEvent(for: &parser, is: .scalar("avg"))
        assertNextEvent(for: &parser, is: .scalar("0.278"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("hr"))
        assertNextEvent(for: &parser, is: .scalar("63"))
        assertNextEvent(for: &parser, is: .scalar("avg"))
        assertNextEvent(for: &parser, is: .scalar("0.288"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_7_TwoDocumentsInAStream() {
        var parser = makeParser(for: example_2_7)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Mark McGwire"))
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .scalar("Ken Griffey"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Chicago Cubs"))
        assertNextEvent(for: &parser, is: .scalar("St Louis Cardinals"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_8_PlayByPlayFeed() {
        var parser = makeParser(for: example_2_8)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("time"))
        assertNextEvent(for: &parser, is: .scalar("20:03:20"))
        assertNextEvent(for: &parser, is: .scalar("player"))
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .scalar("action"))
        assertNextEvent(for: &parser, is: .scalar("strike (miss)"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("time"))
        assertNextEvent(for: &parser, is: .scalar("20:03:47"))
        assertNextEvent(for: &parser, is: .scalar("player"))
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .scalar("action"))
        assertNextEvent(for: &parser, is: .scalar("grand slam"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_9_SingleDocumentWithTwoComments() {
        var parser = makeParser(for: example_2_9)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("hr"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Mark McGwire"))
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .scalar("rbi"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .scalar("Ken Griffey"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_10_SimpleAnchor() {
        var parser = makeParser(for: example_2_10)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("hr"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Mark McGwire"))
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .scalar("rbi"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .alias)
        assertNextEvent(for: &parser, is: .scalar("Ken Griffey"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_11_MappingBetweenSequences() {
        var parser = makeParser(for: example_2_11)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Detroit Tigers"))
        assertNextEvent(for: &parser, is: .scalar("Chicago cubs"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("2001-07-23"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("New York Yankees"))
        assertNextEvent(for: &parser, is: .scalar("Atlanta Braves"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("2001-07-02"))
        assertNextEvent(for: &parser, is: .scalar("2001-08-12"))
        assertNextEvent(for: &parser, is: .scalar("2001-08-14"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_12_CompactNestedMapping() {
        var parser = makeParser(for: example_2_12)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("item"))
        assertNextEvent(for: &parser, is: .scalar("Super Hoop"))
        assertNextEvent(for: &parser, is: .scalar("quantity"))
        assertNextEvent(for: &parser, is: .scalar("1"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("item"))
        assertNextEvent(for: &parser, is: .scalar("Basketball"))
        assertNextEvent(for: &parser, is: .scalar("quantity"))
        assertNextEvent(for: &parser, is: .scalar("4"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("item"))
        assertNextEvent(for: &parser, is: .scalar("Big Shoes"))
        assertNextEvent(for: &parser, is: .scalar("quantity"))
        assertNextEvent(for: &parser, is: .scalar("1"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_13_InLiteralsNewlinesArePreserved() {
        var parser = makeParser(for: example_2_13)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("\\//||\\/||\n// ||  ||__"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_14_InFoldedScalarsNewlinesBecomeSpaces() {
        var parser = makeParser(for: example_2_14)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("Mark McGwire's year was crippled by a knee injury."))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_15_FoldedNewlinesArePreservedForMoreIndentedAndBlankLines() {
        var parser = makeParser(for: example_2_15)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa completed another fine season with great stats.\n\n  63 Home Runs\n  0.288 Batting Average\n\nWhat a year!"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_16_IndentationDeterminesScope() {
        var parser = makeParser(for: example_2_16)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("name"))
        assertNextEvent(for: &parser, is: .scalar("Mark McGwire"))
        assertNextEvent(for: &parser, is: .scalar("accomplishment"))
        assertNextEvent(for: &parser, is: .scalar("Mark set a major league home run record in 1998.\n"))
        assertNextEvent(for: &parser, is: .scalar("stats"))
        assertNextEvent(for: &parser, is: .scalar("65 Home Runs\n0.278 Batting Average\n"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_17_QuotedScalars() {
        var parser = makeParser(for: example_2_17)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("unicode"))
        assertNextEvent(for: &parser, is: .scalar("Sosa did fine.\u{263A}"))
        assertNextEvent(for: &parser, is: .scalar("control"))
        assertNextEvent(for: &parser, is: .scalar("\u{8}1998\t1999\t2000\n"))
        assertNextEvent(for: &parser, is: .scalar("hex esc"))
        assertNextEvent(for: &parser, is: .scalar("\u{0d}\u{0a} is \r\n"))
        assertNextEvent(for: &parser, is: .scalar("single"))
        assertNextEvent(for: &parser, is: .scalar("\"Howdy!\" he cried."))
        assertNextEvent(for: &parser, is: .scalar("quoted"))
        assertNextEvent(for: &parser, is: .scalar(" # Not a 'comment'."))
        assertNextEvent(for: &parser, is: .scalar("tie-fighter"))
        assertNextEvent(for: &parser, is: .scalar("|\\-*-/|"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_18_MultiLineFlowScalars() {
        var parser = makeParser(for: example_2_18)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("plain"))
        assertNextEvent(for: &parser, is: .scalar("This unquoted scalar spans many lines."))
        assertNextEvent(for: &parser, is: .scalar("quoted"))
        assertNextEvent(for: &parser, is: .scalar("So does this quoted scalar.\n"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_23_VariousExplicitTags() {
        var parser = makeParser(for: example_2_23)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("not-date"))
        assertNextEvent(for: &parser, is: .scalar("2002-04-28", tag: "tag:yaml.org,2002:str"))
        assertNextEvent(for: &parser, is: .scalar("picture"))
        assertNextEvent(for: &parser, is: .scalar("R0lGODlhDAAMAIQAAP//9/X\n17unp5WZmZgAAAOfn515eXv\nPz7Y6OjuDg4J+fn5OTk6enp\n56enmleECcgggoBADs=\n", tag: "tag:yaml.org,2002:binary"))
        assertNextEvent(for: &parser, is: .scalar("application specific tag"))
        assertNextEvent(for: &parser, is: .scalar("The semantics of the tag\nabove may be different for\ndifferent documents.", tag: "!something"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_24_GlobalTags() {
        var parser = makeParser(for: example_2_24)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block, tag: "tag:clarkevans.com,2002:shape"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block, tag: "tag:clarkevans.com,2002:circle"))
        assertNextEvent(for: &parser, is: .scalar("center"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("x"))
        assertNextEvent(for: &parser, is: .scalar("73"))
        assertNextEvent(for: &parser, is: .scalar("y"))
        assertNextEvent(for: &parser, is: .scalar("129"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .scalar("radius"))
        assertNextEvent(for: &parser, is: .scalar("7"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block, tag: "tag:clarkevans.com,2002:line"))
        assertNextEvent(for: &parser, is: .scalar("start"))
        assertNextEvent(for: &parser, is: .alias)
        assertNextEvent(for: &parser, is: .scalar("finish"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("x"))
        assertNextEvent(for: &parser, is: .scalar("89"))
        assertNextEvent(for: &parser, is: .scalar("y"))
        assertNextEvent(for: &parser, is: .scalar("102"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block, tag: "tag:clarkevans.com,2002:label"))
        assertNextEvent(for: &parser, is: .scalar("start"))
        assertNextEvent(for: &parser, is: .alias)
        assertNextEvent(for: &parser, is: .scalar("color"))
        assertNextEvent(for: &parser, is: .scalar("0xFFEEBB"))
        assertNextEvent(for: &parser, is: .scalar("text"))
        assertNextEvent(for: &parser, is: .scalar("Pretty vector drawing."))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_25_UnorderedSets() {
        var parser = makeParser(for: example_2_25)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block, tag: "tag:yaml.org,2002:set"))
        assertNextEvent(for: &parser, is: .scalar("Mark McGwire"))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .scalar("Ken Griffey"))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_26_OrderedMappings() {
        var parser = makeParser(for: example_2_26)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block, tag: "tag:yaml.org,2002:omap"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Mark McGwire"))
        assertNextEvent(for: &parser, is: .scalar("65"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Sammy Sosa"))
        assertNextEvent(for: &parser, is: .scalar("63"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Ken Griffey"))
        assertNextEvent(for: &parser, is: .scalar("58"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_27_Invoice() {
        var parser = makeParser(for: example_2_27)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block, tag: "tag:clarkevans.com,2002:invoice"))
        assertNextEvent(for: &parser, is: .scalar("invoice"))
        assertNextEvent(for: &parser, is: .scalar("34843"))
        assertNextEvent(for: &parser, is: .scalar("date"))
        assertNextEvent(for: &parser, is: .scalar("2001-01-23"))
        assertNextEvent(for: &parser, is: .scalar("bill-to"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("given"))
        assertNextEvent(for: &parser, is: .scalar("Chris"))
        assertNextEvent(for: &parser, is: .scalar("family"))
        assertNextEvent(for: &parser, is: .scalar("Dumars"))
        assertNextEvent(for: &parser, is: .scalar("address"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("lines"))
        assertNextEvent(for: &parser, is: .scalar("458 Walkman Dr.\nSuite #292\n"))
        assertNextEvent(for: &parser, is: .scalar("city"))
        assertNextEvent(for: &parser, is: .scalar("Royal Oak"))
        assertNextEvent(for: &parser, is: .scalar("state"))
        assertNextEvent(for: &parser, is: .scalar("MI"))
        assertNextEvent(for: &parser, is: .scalar("postal"))
        assertNextEvent(for: &parser, is: .scalar("48046"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .scalar("ship-to"))
        assertNextEvent(for: &parser, is: .alias)
        assertNextEvent(for: &parser, is: .scalar("product"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("sku"))
        assertNextEvent(for: &parser, is: .scalar("BL394D"))
        assertNextEvent(for: &parser, is: .scalar("quantity"))
        assertNextEvent(for: &parser, is: .scalar("4"))
        assertNextEvent(for: &parser, is: .scalar("description"))
        assertNextEvent(for: &parser, is: .scalar("Basketball"))
        assertNextEvent(for: &parser, is: .scalar("price"))
        assertNextEvent(for: &parser, is: .scalar("450.00"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("sku"))
        assertNextEvent(for: &parser, is: .scalar("BL4438H"))
        assertNextEvent(for: &parser, is: .scalar("quantity"))
        assertNextEvent(for: &parser, is: .scalar("1"))
        assertNextEvent(for: &parser, is: .scalar("description"))
        assertNextEvent(for: &parser, is: .scalar("Super Hoop"))
        assertNextEvent(for: &parser, is: .scalar("price"))
        assertNextEvent(for: &parser, is: .scalar("2392.00"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .scalar("tax"))
        assertNextEvent(for: &parser, is: .scalar("251.42"))
        assertNextEvent(for: &parser, is: .scalar("total"))
        assertNextEvent(for: &parser, is: .scalar("4443.52"))
        assertNextEvent(for: &parser, is: .scalar("comments"))
        assertNextEvent(for: &parser, is: .scalar("Late afternoon is best. Backup contact is Nancy Billsmer @ 338-4338."))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_2_28_LogFile() {
        var parser = makeParser(for: example_2_28)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Time"))
        assertNextEvent(for: &parser, is: .scalar("2001-11-23 15:01:42 -5"))
        assertNextEvent(for: &parser, is: .scalar("User"))
        assertNextEvent(for: &parser, is: .scalar("ed"))
        assertNextEvent(for: &parser, is: .scalar("Warning"))
        assertNextEvent(for: &parser, is: .scalar("This is an error message for the log file"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Time"))
        assertNextEvent(for: &parser, is: .scalar("2001-11-23 15:02:31 -5"))
        assertNextEvent(for: &parser, is: .scalar("User"))
        assertNextEvent(for: &parser, is: .scalar("ed"))
        assertNextEvent(for: &parser, is: .scalar("Warning"))
        assertNextEvent(for: &parser, is: .scalar("A slightly different error message."))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Date"))
        assertNextEvent(for: &parser, is: .scalar("2001-11-23 15:03:17 -5"))
        assertNextEvent(for: &parser, is: .scalar("User"))
        assertNextEvent(for: &parser, is: .scalar("ed"))
        assertNextEvent(for: &parser, is: .scalar("Fatal"))
        assertNextEvent(for: &parser, is: .scalar("Unknown variable \"bar\""))
        assertNextEvent(for: &parser, is: .scalar("Stack"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("file"))
        assertNextEvent(for: &parser, is: .scalar("TopClass.py"))
        assertNextEvent(for: &parser, is: .scalar("line"))
        assertNextEvent(for: &parser, is: .scalar("23"))
        assertNextEvent(for: &parser, is: .scalar("code"))
        assertNextEvent(for: &parser, is: .scalar("x = MoreObject(\"345\\n\")\n"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("file"))
        assertNextEvent(for: &parser, is: .scalar("MoreClass.py"))
        assertNextEvent(for: &parser, is: .scalar("line"))
        assertNextEvent(for: &parser, is: .scalar("58"))
        assertNextEvent(for: &parser, is: .scalar("code"))
        assertNextEvent(for: &parser, is: .scalar("foo = bar"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    // MARK: - Characters

    private let example_5_3 = "sequence:\n- one\n- two\nmapping:\n  ? sky\n  : blue\n  sea : green"
    private let example_5_4 = "sequence: [ one, two, ]\nmapping: { sky: blue, sea: green }"
    private let example_5_5 = "# Comment only."
    private let example_5_6 = "anchored: !local &anchor value\nalias: *anchor"
    private let example_5_7 = "literal: |\n  some\n  text\nfolded: >\n  some\n  text\n"
    private let example_5_8 = "single: 'text'\ndouble: \"text\""
    private let example_5_9 = "%YAML 1.2\n--- text"
    private let example_5_10a = "commercial-at: @text"
    private let example_5_10b = "grave-accent: `text"
    private let example_5_11 = "|\n  Line break (no glyph)\n  Line break (glyphed)\n"
    private let example_5_12 = "# Tabs and spaces\nquoted: \"Quoted\t\"\nblock:\t|\n  void main() {\n  \tprintf(\"Hello, world!\\n\");\n  }"
    private let example_5_13 = "\"Fun with \\\\\n\\\" \\a \\b \\e \\f \\\n\\n \\r \\t \\v \\0 \\\n\\  \\_ \\N \\L \\P \\\n\\x41 \\u0041 \\U00000041\""
    private let example_5_14 = "Bad escapes:\n  \"\\c\n  \\xq-\""

    func testExample_5_3_BlockStructureIndicators() {
        var parser = makeParser(for: example_5_3)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("sequence"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("one"))
        assertNextEvent(for: &parser, is: .scalar("two"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .scalar("mapping"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("sky"))
        assertNextEvent(for: &parser, is: .scalar("blue"))
        assertNextEvent(for: &parser, is: .scalar("sea"))
        assertNextEvent(for: &parser, is: .scalar("green"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_5_4_FlowStructureIndicators() {
        var parser = makeParser(for: example_5_4)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("sequence"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("one"))
        assertNextEvent(for: &parser, is: .scalar("two"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .scalar("mapping"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("sky"))
        assertNextEvent(for: &parser, is: .scalar("blue"))
        assertNextEvent(for: &parser, is: .scalar("sea"))
        assertNextEvent(for: &parser, is: .scalar("green"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_5_6_NodePropertyIndicators() {
        var parser = makeParser(for: example_5_6)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("anchored"))
        assertNextEvent(for: &parser, is: .scalar("value", tag: "!local"))
        assertNextEvent(for: &parser, is: .scalar("alias"))
        assertNextEvent(for: &parser, is: .alias)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_5_7_BlockScalarIndicators() {
        var parser = makeParser(for: example_5_7)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("literal"))
        assertNextEvent(for: &parser, is: .scalar("some\ntext\n"))
        assertNextEvent(for: &parser, is: .scalar("folded"))
        assertNextEvent(for: &parser, is: .scalar("some text\n"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_5_8_QuotedScalarIndicators() {
        var parser = makeParser(for: example_5_8)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("single"))
        assertNextEvent(for: &parser, is: .scalar("text"))
        assertNextEvent(for: &parser, is: .scalar("double"))
        assertNextEvent(for: &parser, is: .scalar("text"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_5_9_DirectiveIndicators() {
        var parser = makeParser(for: example_5_9)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("text"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_5_10_ReservedIndicators() {
        var parser = makeParser(for: example_5_10a)
        assertError(fromConsuming: &parser) { (error) in
            XCTAssertEqual(error.code, .invalidToken)
        }

        parser = makeParser(for: example_5_10b)
        assertError(fromConsuming: &parser) { (error) in
            XCTAssertEqual(error.code, .invalidToken)
        }
    }

    func testExample_5_11_LineBreakCharacters() {
        var parser = makeParser(for: example_5_11)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("Line break (no glyph)\nLine break (glyphed)\n"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_5_12_TabsAndSpaces() {
        var parser = makeParser(for: example_5_12)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("quoted"))
        assertNextEvent(for: &parser, is: .scalar("Quoted\t"))
        assertNextEvent(for: &parser, is: .scalar("block"))
        assertNextEvent(for: &parser, is: .scalar("void main() {\n\tprintf(\"Hello, world!\\n\");\n}"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_5_13_EscapedCharacters() {
        var parser = makeParser(for: example_5_13)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("Fun with \\ \" \u{07} \u{08} \u{1b} \u{0c} \n \r \t \u{0b} \0   \u{a0} \u{85} \u{2028} \u{2029} A A A"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_5_14_InvalidEscapedCharacters() {
        var parser = makeParser(for: example_5_14)
        assertError(fromConsuming: &parser) { (error) in
            XCTAssertEqual(error.code, .invalidEscape)
        }
    }

    // MARK: - Basic Structures

    private let example_6_1 = "  # Leading comment line spaces are\n   # neither content nor indentation.\n    \nNot indented:\n By one space: |\n    By four\n      spaces\n Flow style: [    # Leading spaces\n   By two,        # in flow style\n  Also by two,    # are neither\n  \tStill by two   # content nor\n    ]             # indentation."
    private let example_6_2 = "? a\n: -\tb\n  -  -\tc\n     - d"
    private let example_6_3 = "- foo:\t bar\n- - baz\n  -\tbaz"
    private let example_6_4 = "plain: text\n  lines\nquoted: \"text\n  \tlines\"\nblock: |\n  text\n   \tlines\n"
    private let example_6_5 = "Folding:\n  \"Empty line\n   \t\n  as a line feed\"\nChomping: |\n  Clipped empty lines\n "
    private let example_6_6 = ">-\n  trimmed\n  \n \n\n  as\n  space"
    private let example_6_7 = ">\n  foo \n \n  \t bar\n\n  baz\n"
    private let example_6_8 = "\"\n  foo \n \n  \t bar\n\n  baz\n\""
    private let example_6_9 = "key:    # Comment\n  value"
    private let example_6_10 = "  # Comment\n   \n\n"
    private let example_6_11 = "key:    # Comment\n        # lines\n  value\n\n"
    private let example_6_12 = "{ first: Sammy, last: Sosa }:\n# Statistics:\n  hr:  # Home runs\n     65\n  avg: # Average\n   0.278"
    private let example_6_13 = "%FOO  bar baz # Should be ignored\n               # with a warning.\n--- \"foo\""
    private let example_6_14 = "%YAML 1.3 # Attempt parsing\n           # with a warning\n---\n\"foo\""
    private let example_6_15 = "%YAML 1.2\n%YAML 1.1\nfoo"
    private let example_6_16 = "%TAG !yaml! tag:yaml.org,2002:\n---\n!yaml!str \"foo\""
    private let example_6_17 = "%TAG ! !foo\n%TAG ! !foo\nbar"
    private let example_6_18 = "# Private\n!foo \"bar\"\n...\n# Global\n%TAG ! tag:example.com,2000:app/\n---\n!foo \"bar\""
    private let example_6_19 = "%TAG !! tag:example.com,2000:app/\n---\n!!int 1 - 3 # Interval, not integer"
    private let example_6_20 = "%TAG !e! tag:example.com,2000:app/\n---\n!e!foo \"bar\""
    private let example_6_21 = "%TAG !m! !my-\n--- # Bulb here\n!m!light fluorescent\n...\n%TAG !m! !my-\n--- # Color here\n!m!light green"
    private let example_6_22 = "%TAG !e! tag:example.com,2000:app/\n---\n- !e!foo \"bar\""
    private let example_6_23 = "!!str &a1 \"foo\":\n  !!str bar\n&a2 baz : *a1"
    private let example_6_24 = "!<tag:yaml.org,2002:str> foo :\n  !<!bar> baz"
    private let example_6_25 = "- !<!> foo\n- !<$:?> bar\n"
    private let example_6_26 = "%TAG !e! tag:example.com,2000:app/\n---\n- !local foo\n- !!str bar\n- !e!tag%21 baz\n"
    private let example_6_27a = "%TAG !e! tag:example,2000:app/\n---\n- !e! foo"
    private let example_6_27b = "%TAG !e! tag:example,2000:app/\n---\n- !h!bar baz"
    private let example_6_28 = "# Assuming conventional resolution:\n- \"12\"\n- 12\n- ! 12"
    private let example_6_29 = "First occurrence: &anchor Value\nSecond occurrence: *anchor"

    func testExample_6_1_IndentationSpaces() {
        var parser = makeParser(for: example_6_1)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Not indented"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("By one space"))
        assertNextEvent(for: &parser, is: .scalar("By four\n  spaces\n"))
        assertNextEvent(for: &parser, is: .scalar("Flow style"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("By two"))
        assertNextEvent(for: &parser, is: .scalar("Also by two"))
        assertNextEvent(for: &parser, is: .scalar("Still by two"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_2_IndentationIndicators() {
        var parser = makeParser(for: example_6_2)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("a"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("b"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("c"))
        assertNextEvent(for: &parser, is: .scalar("d"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_3_SeparationSpaces() {
        var parser = makeParser(for: example_6_3)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("foo"))
        assertNextEvent(for: &parser, is: .scalar("bar"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("baz"))
        assertNextEvent(for: &parser, is: .scalar("baz"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_4_LinePrefixes() {
        var parser = makeParser(for: example_6_4)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("plain"))
        assertNextEvent(for: &parser, is: .scalar("text lines"))
        assertNextEvent(for: &parser, is: .scalar("quoted"))
        assertNextEvent(for: &parser, is: .scalar("text lines"))
        assertNextEvent(for: &parser, is: .scalar("block"))
        assertNextEvent(for: &parser, is: .scalar("text\n \tlines\n"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_5_EmptyLines() {
        var parser = makeParser(for: example_6_5)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("Folding"))
        assertNextEvent(for: &parser, is: .scalar("Empty line\nas a line feed"))
        assertNextEvent(for: &parser, is: .scalar("Chomping"))
        assertNextEvent(for: &parser, is: .scalar("Clipped empty lines\n"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_6_LineFolding() {
        var parser = makeParser(for: example_6_6)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("trimmed\n\n\nas space"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_7_BlockFolding() {
        var parser = makeParser(for: example_6_7)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("foo \n\n\t bar\n\nbaz\n"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_8_FlowFolding() {
        var parser = makeParser(for: example_6_8)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar(" foo\nbar\nbaz "))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_9_SeparatedComment() {
        var parser = makeParser(for: example_6_9)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("key"))
        assertNextEvent(for: &parser, is: .scalar("value"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_11_MultiLineComments() {
        var parser = makeParser(for: example_6_11)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("key"))
        assertNextEvent(for: &parser, is: .scalar("value"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_12_SeparationSpacesII() {
        var parser = makeParser(for: example_6_12)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("first"))
        assertNextEvent(for: &parser, is: .scalar("Sammy"))
        assertNextEvent(for: &parser, is: .scalar("last"))
        assertNextEvent(for: &parser, is: .scalar("Sosa"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("hr"))
        assertNextEvent(for: &parser, is: .scalar("65"))
        assertNextEvent(for: &parser, is: .scalar("avg"))
        assertNextEvent(for: &parser, is: .scalar("0.278"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_13_ReservedDirectives() {
        var parser = makeParser(for: example_6_13)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("foo"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_14_YAMLDirective() {
        var parser = makeParser(for: example_6_14)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("foo"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_15_InvalidRepeatedYAMLDirective() {
        var parser = makeParser(for: example_6_15)
        assertError(fromConsuming: &parser) { (error) in
            XCTAssertEqual(error.code, .unexpectedDirective)
        }
    }

    func testExample_6_16_TagDirective() {
        var parser = makeParser(for: example_6_16)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("foo", tag: "tag:yaml.org,2002:str"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_17_InvalidRepeatedTagDirective() {
        var parser = makeParser(for: example_6_17)
        assertError(fromConsuming: &parser) { (error) in
            XCTAssertEqual(error.code, .unexpectedDirective)
        }
    }

    func testExample_6_18_PrimaryTagHandle() {
        var parser = makeParser(for: example_6_18)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("bar", tag: "!foo"))
        assertNextEvent(for: &parser, is: .documentEnd)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("bar", tag: "tag:example.com,2000:app/foo"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_19_SecondaryTagHandle() {
        var parser = makeParser(for: example_6_19)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("1 - 3", tag: "tag:example.com,2000:app/int"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_20_TagHandles() {
        var parser = makeParser(for: example_6_20)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("bar", tag: "tag:example.com,2000:app/foo"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_21_LocalTagPrefix() {
        var parser = makeParser(for: example_6_21)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("fluorescent", tag: "!my-light"))
        assertNextEvent(for: &parser, is: .documentEnd)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("green", tag: "!my-light"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_22_GlobalTagPrefix() {
        var parser = makeParser(for: example_6_22)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("bar", tag: "tag:example.com,2000:app/foo"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_23_NodeProperties() {
        var parser = makeParser(for: example_6_23)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("foo", tag: "tag:yaml.org,2002:str"))
        assertNextEvent(for: &parser, is: .scalar("bar", tag: "tag:yaml.org,2002:str"))
        assertNextEvent(for: &parser, is: .scalar("baz"))
        assertNextEvent(for: &parser, is: .alias)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_24_VerbatimTags() {
        var parser = makeParser(for: example_6_24)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("foo", tag: "tag:yaml.org,2002:str"))
        assertNextEvent(for: &parser, is: .scalar("baz", tag: "!bar"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_26_TagShorthands() {
        var parser = makeParser(for: example_6_26)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("foo", tag: "!local"))
        assertNextEvent(for: &parser, is: .scalar("bar", tag: "tag:yaml.org,2002:str"))
        assertNextEvent(for: &parser, is: .scalar("baz", tag: "tag:example.com,2000:app/tag!"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_27a_InvalidTagShorthands() {
        var parser = makeParser(for: example_6_27a)
        assertError(fromConsuming: &parser) { (error) in
            XCTAssertEqual(error.code, .tagFormat)
        }
    }

    func testExample_6_28_NonSpecificTags() {
        var parser = makeParser(for: example_6_28)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("12"))
        assertNextEvent(for: &parser, is: .scalar("12"))
        assertNextEvent(for: &parser, is: .scalar("12", tag: "!"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_6_29_NodeAnchors() {
        var parser = makeParser(for: example_6_29)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("First occurrence"))
        assertNextEvent(for: &parser, is: .scalar("Value"))
        assertNextEvent(for: &parser, is: .scalar("Second occurrence"))
        assertNextEvent(for: &parser, is: .alias)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    // MARK: - Flow Styles

    private let example_7_1 = "First occurrence: &anchor Foo\nSecond occurrence: *anchor\nOverride anchor: &anchor Bar\nReuse anchor: *anchor"
    private let example_7_2 = "{\n  foo : !!str,\n  !!str : bar,\n}"
    private let example_7_3 = "{\n  ? foo :,\n  : bar,\n}\n"
    private let example_7_4 = "\"implicit block key\" : [\n  \"implicit flow key\" : value,\n ]"
    private let example_7_5 = "\"folded \nto a space,\t\n \nto a line feed, or \t\\\n \\ \tnon-content\""
    private let example_7_6 = "\" 1st non-empty\n\n 2nd non-empty \n\t3rd non-empty \""
    private let example_7_7 = " 'here''s to \"quotes\"'"
    private let example_7_8 = "'implicit block key' : [\n  'implicit flow key' : value,\n ]"
    private let example_7_9 = "' 1st non-empty\n\n 2nd non-empty \n\t3rd non-empty '"
    private let example_7_10 = "# Outside flow collection:\n- ::vector\n- \": - ()\"\n- Up, up, and away!\n- -123\n- http://example.com/foo#bar\n# Inside flow collection:\n- [ ::vector,\n  \": - ()\",\n  \"Up, up, and away!\",\n  -123,\n  http://example.com/foo#bar ]"
    private let example_7_11 = "implicit block key : [\n  implicit flow key : value,\n ]"
    private let example_7_12 = "1st non-empty\n\n 2nd non-empty \n\t3rd non-empty"
    private let example_7_13 = "- [ one, two, ]\n- [three ,four]"
    private let example_7_14 = "[\n\"double\n quoted\", 'single\n           quoted',\nplain\n text, [ nested ],\nsingle: pair,\n]"
    private let example_7_15 = "- { one : two , three: four , }\n- {five: six,seven : eight}"
    private let example_7_16 = "{\n? explicit: entry,\nimplicit: entry,\n?\n}"
    private let example_7_17 = "{\nunquoted : \"separate\",\nhttp://foo.com,\nomitted value:,\n: omitted key,\n}"
    private let example_7_18 = "{\n\"adjacent\":value,\n\"readable\":value,\n\"empty\":\n}"
    private let example_7_19 = "[\nfoo: bar\n]"
    private let example_7_20 = "[\n? foo\n bar : baz\n]"
    private let example_7_21 = "- [ YAML : separate ]\n- [ : empty key entry ]\n- [ {JSON: like}:adjacent ]"
    private let example_7_22 = "[ foo\n bar: invalid,"
    private let example_7_23 = "- [ a, b ]\n- { a: b }\n- \"a\"\n- 'b'\n- c"
    private let example_7_24 = "- !!str \"a\"\n- 'b'\n- &anchor \"c\"\n- *anchor\n- !!str"

    func testExample_7_1_AliasNodes() {
        var parser = makeParser(for: example_7_1)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("First occurrence"))
        assertNextEvent(for: &parser, is: .scalar("Foo"))
        assertNextEvent(for: &parser, is: .scalar("Second occurrence"))
        assertNextEvent(for: &parser, is: .alias)
        assertNextEvent(for: &parser, is: .scalar("Override anchor"))
        assertNextEvent(for: &parser, is: .scalar("Bar"))
        assertNextEvent(for: &parser, is: .scalar("Reuse anchor"))
        assertNextEvent(for: &parser, is: .alias)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_2_EmptyNodes() {
        var parser = makeParser(for: example_7_2)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("foo"))
        assertNextEvent(for: &parser, is: .scalar("", tag: "tag:yaml.org,2002:str"))
        assertNextEvent(for: &parser, is: .scalar("", tag: "tag:yaml.org,2002:str"))
        assertNextEvent(for: &parser, is: .scalar("bar"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_3_CompletelyEmptyNodes() {
        var parser = makeParser(for: example_7_3)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("foo"))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .scalar("bar"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_4_DoubleQuotedImplicitKeys() {
        var parser = makeParser(for: example_7_4)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("implicit block key"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("implicit flow key"))
        assertNextEvent(for: &parser, is: .scalar("value"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_5_DoubleQuotedLineBreaks() {
        var parser = makeParser(for: example_7_5)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("folded to a space,\nto a line feed, or \t \tnon-content"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_6_DoubleQuotedLines() {
        var parser = makeParser(for: example_7_6)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar(" 1st non-empty\n2nd non-empty 3rd non-empty "))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_7_SingleQuotedCharacters() {
        var parser = makeParser(for: example_7_7)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("here's to \"quotes\""))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_8_SingleQuotedImplicitKeys() {
        var parser = makeParser(for: example_7_8)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("implicit block key"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("implicit flow key"))
        assertNextEvent(for: &parser, is: .scalar("value"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_9_SingleQuotedLines() {
        var parser = makeParser(for: example_7_9)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar(" 1st non-empty\n2nd non-empty 3rd non-empty "))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_10_PlainCharacters() {
        var parser = makeParser(for: example_7_10)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("::vector"))
        assertNextEvent(for: &parser, is: .scalar(": - ()"))
        assertNextEvent(for: &parser, is: .scalar("Up, up, and away!"))
        assertNextEvent(for: &parser, is: .scalar("-123"))
        assertNextEvent(for: &parser, is: .scalar("http://example.com/foo#bar"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("::vector"))
        assertNextEvent(for: &parser, is: .scalar(": - ()"))
        assertNextEvent(for: &parser, is: .scalar("Up, up, and away!"))
        assertNextEvent(for: &parser, is: .scalar("-123"))
        assertNextEvent(for: &parser, is: .scalar("http://example.com/foo#bar"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_11_PlainImplicitKeys() {
        var parser = makeParser(for: example_7_11)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("implicit block key"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("implicit flow key"))
        assertNextEvent(for: &parser, is: .scalar("value"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_12_PlainLines() {
        var parser = makeParser(for: example_7_12)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("1st non-empty\n2nd non-empty 3rd non-empty"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_13_FlowSequence() {
        var parser = makeParser(for: example_7_13)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("one"))
        assertNextEvent(for: &parser, is: .scalar("two"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("three"))
        assertNextEvent(for: &parser, is: .scalar("four"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_14_FlowSequenceEntries() {
        var parser = makeParser(for: example_7_14)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("double quoted"))
        assertNextEvent(for: &parser, is: .scalar("single quoted"))
        assertNextEvent(for: &parser, is: .scalar("plain text"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("nested"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("single"))
        assertNextEvent(for: &parser, is: .scalar("pair"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_15_FlowMappings() {
        var parser = makeParser(for: example_7_15)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("one"))
        assertNextEvent(for: &parser, is: .scalar("two"))
        assertNextEvent(for: &parser, is: .scalar("three"))
        assertNextEvent(for: &parser, is: .scalar("four"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("five"))
        assertNextEvent(for: &parser, is: .scalar("six"))
        assertNextEvent(for: &parser, is: .scalar("seven"))
        assertNextEvent(for: &parser, is: .scalar("eight"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_16_FlowMappingEntries() {
        var parser = makeParser(for: example_7_16)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("explicit"))
        assertNextEvent(for: &parser, is: .scalar("entry"))
        assertNextEvent(for: &parser, is: .scalar("implicit"))
        assertNextEvent(for: &parser, is: .scalar("entry"))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_17_FlowMappingSeparateValues() {
        var parser = makeParser(for: example_7_17)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("unquoted"))
        assertNextEvent(for: &parser, is: .scalar("separate"))
        assertNextEvent(for: &parser, is: .scalar("http://foo.com"))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .scalar("omitted value"))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .scalar("omitted key"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_18_FlowMappingAdjacentValues() {
        var parser = makeParser(for: example_7_18)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("adjacent"))
        assertNextEvent(for: &parser, is: .scalar("value"))
        assertNextEvent(for: &parser, is: .scalar("readable"))
        assertNextEvent(for: &parser, is: .scalar("value"))
        assertNextEvent(for: &parser, is: .scalar("empty"))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_19_SinglePairFlowMappings() {
        var parser = makeParser(for: example_7_19)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("foo"))
        assertNextEvent(for: &parser, is: .scalar("bar"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_20_SinglePairExplicitEntry() {
        var parser = makeParser(for: example_7_20)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("foo bar"))
        assertNextEvent(for: &parser, is: .scalar("baz"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_21_SinglePairImplicitEntries() {
        var parser = makeParser(for: example_7_21)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("YAML"))
        assertNextEvent(for: &parser, is: .scalar("separate"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .scalar("empty key entry"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("JSON"))
        assertNextEvent(for: &parser, is: .scalar("like"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .scalar("adjacent"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_22_InvalidImplicitKeys() {
        var parser = makeParser(for: example_7_22)
        assertError(fromConsuming: &parser) { (error) in
            XCTAssertEqual(error.code, .invalidToken)
        }
    }

    func testExample_7_23_FlowContent() {
        var parser = makeParser(for: example_7_23)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("a"))
        assertNextEvent(for: &parser, is: .scalar("b"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .flow))
        assertNextEvent(for: &parser, is: .scalar("a"))
        assertNextEvent(for: &parser, is: .scalar("b"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .scalar("a"))
        assertNextEvent(for: &parser, is: .scalar("b"))
        assertNextEvent(for: &parser, is: .scalar("c"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_7_24_FlowNodes() {
        var parser = makeParser(for: example_7_24)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("a", tag: "tag:yaml.org,2002:str"))
        assertNextEvent(for: &parser, is: .scalar("b"))
        assertNextEvent(for: &parser, is: .scalar("c"))
        assertNextEvent(for: &parser, is: .alias)
        assertNextEvent(for: &parser, is: .scalar("", tag: "tag:yaml.org,2002:str"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    // MARK: - Block Styles

    private let example_8_1 = "- | # Empty header\n literal\n- >1 # Indentation indicator\n  folded\n- |+ # Chomping indicator\n keep\n\n- >1- # Both indicators\n  strip\n"
    private let example_8_2 = "- |\n detected\n- >\n \n  \n  # detected\n- |1\n  explicit\n- >\n \t\n detected\n"
    private let example_8_3a = "- |\n  \n text"
    private let example_8_3b = "- >\n  text\n text"
    private let example_8_3c = "- |2\n text"
    private let example_8_4 = "strip: |-\n  text\nclip: |\n  text\nkeep: |+\n  text\n"
    private let example_8_5 = " # Strip\n  # Comments:\nstrip: |-\n  # text\n  \n # Clip\n  # comments:\n\nclip: |\n  # text\n \n # Keep\n  # comments:\n\nkeep: |+\n  # text\n\n # Trail\n  # Comments\n"
    private let example_8_6 = "strip: >-\n\nclip: >\n\nkeep: |+\n\n"
    private let example_8_7 = "|\n literal\n \ttext\n\n"
    private let example_8_8 = "|\n \n  \n  literal\n   \n  \n  text\n\n # Comment\n"
    private let example_8_9 = ">\n folded\n text\n\n"
    private let example_8_10 = ">\n\n folded\n line\n\n next\n line\n   * bullet\n\n   * list\n   * lines\n\n last\n line\n\n# Comment\n"
    private var example_8_11: String { return example_8_10 }
    private var example_8_12: String { return example_8_10 }
    private var example_8_13: String { return example_8_10 }
    private let example_8_14 = "block sequence:\n  - one\n  - two : three\n"
    private let example_8_15 = "- # Empty\n- |\n block node\n- - one # Compact\n  - two # sequence\n- one: two # Compact mapping\n"
    private let example_8_16 = "block mapping:\n key: value\n"
    private let example_8_17 = "? explicit key # Empty value\n? |\n  block key\n: - one # Explicit compact\n  - two # block value\n"
    private let example_8_18 = "plain key: in-line value\n:  # Both empty\n\"quoted key\":\n- entry\n"
    private let example_8_19 = "- sun: yellow\n- ? earth: blue\n  : moon: white\n"
    private let example_8_20 = "-\n  \"flow in block\"\n- >\n Block scalar\n- !!map # Block collection\n  foo : bar\n"
    private let example_8_21 = "literal: |2\n  value\nfolded:\n   !foo\n  >1\n value"
    private let example_8_22 = "sequence: !!seq\n- entry\n- !!seq\n - nested\nmapping: !!map\n foo: bar\n"

    func testExample_8_1_BlockScalarHeader() {
        var parser = makeParser(for: example_8_1)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("literal\n"))
        assertNextEvent(for: &parser, is: .scalar(" folded\n"))
        assertNextEvent(for: &parser, is: .scalar("keep\n\n"))
        assertNextEvent(for: &parser, is: .scalar(" strip"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_2_BlockIndentationHeader() {
        var parser = makeParser(for: example_8_2)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("detected\n"))
        assertNextEvent(for: &parser, is: .scalar("\n\n# detected\n"))
        assertNextEvent(for: &parser, is: .scalar(" explicit\n"))
        assertNextEvent(for: &parser, is: .scalar("\t\ndetected\n"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }
    
    func testExample_8_3a_InvalidBlockScalarIndentationIndicators() {
        var parser = makeParser(for: example_8_3a)
        assertError(fromConsuming: &parser)
    }

    func testExample_8_3b_InvalidBlockScalarIndentationIndicators() {
        var parser = makeParser(for: example_8_3b)
        assertError(fromConsuming: &parser)
    }

    func testExample_8_3c_InvalidBlockScalarIndentationIndicators() {
        var parser = makeParser(for: example_8_3c)
        assertError(fromConsuming: &parser)
    }

    func testExample_8_4_ChompingFinalLineBreak() {
        var parser = makeParser(for: example_8_4)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("strip"))
        assertNextEvent(for: &parser, is: .scalar("text"))
        assertNextEvent(for: &parser, is: .scalar("clip"))
        assertNextEvent(for: &parser, is: .scalar("text\n"))
        assertNextEvent(for: &parser, is: .scalar("keep"))
        assertNextEvent(for: &parser, is: .scalar("text\n"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_5_ChompingTrailingLines() {
        var parser = makeParser(for: example_8_5)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("strip"))
        assertNextEvent(for: &parser, is: .scalar("# text"))
        assertNextEvent(for: &parser, is: .scalar("clip"))
        assertNextEvent(for: &parser, is: .scalar("# text\n"))
        assertNextEvent(for: &parser, is: .scalar("keep"))
        assertNextEvent(for: &parser, is: .scalar("# text\n\n"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_6_EmptyScalarChomping() {
        var parser = makeParser(for: example_8_6)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("strip"))
        assertNextEvent(for: &parser, is: .scalar(""))
        assertNextEvent(for: &parser, is: .scalar("clip"))
        assertNextEvent(for: &parser, is: .scalar(""))
        assertNextEvent(for: &parser, is: .scalar("keep"))
        assertNextEvent(for: &parser, is: .scalar("\n"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_7_LiteralScalar() {
        var parser = makeParser(for: example_8_7)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("literal\n\ttext\n"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_8_LiteralContent() {
        var parser = makeParser(for: example_8_8)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("\n\nliteral\n \n\ntext\n"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_9_FoldedScalar() {
        var parser = makeParser(for: example_8_9)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("folded text\n"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_10_FoldedLines() {
        var parser = makeParser(for: example_8_10)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("\nfolded line\nnext line\n  * bullet\n\n  * list\n  * lines\n\nlast line\n"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_11_MoreIndentedLines() {
        var parser = makeParser(for: example_8_11)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("\nfolded line\nnext line\n  * bullet\n\n  * list\n  * lines\n\nlast line\n"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_12_EmptySeparationLines() {
        var parser = makeParser(for: example_8_12)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("\nfolded line\nnext line\n  * bullet\n\n  * list\n  * lines\n\nlast line\n"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_13_FinalEmptyLines() {
        var parser = makeParser(for: example_8_13)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .scalar("\nfolded line\nnext line\n  * bullet\n\n  * list\n  * lines\n\nlast line\n"))
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_14_BlockSequence() {
        var parser = makeParser(for: example_8_14)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("block sequence"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("one"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("two"))
        assertNextEvent(for: &parser, is: .scalar("three"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_15_BlockSequenceEntryTypes() {
        var parser = makeParser(for: example_8_15)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .scalar("block node\n"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("one"))
        assertNextEvent(for: &parser, is: .scalar("two"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("one"))
        assertNextEvent(for: &parser, is: .scalar("two"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_16_BlockMappings() {
        var parser = makeParser(for: example_8_16)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("block mapping"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("key"))
        assertNextEvent(for: &parser, is: .scalar("value"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_17_ExplicitBlockMappingEntries() {
        var parser = makeParser(for: example_8_17)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("explicit key"))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .scalar("block key\n"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("one"))
        assertNextEvent(for: &parser, is: .scalar("two"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_18_ImplicitBlockMappingEntries() {
        var parser = makeParser(for: example_8_18)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("plain key"))
        assertNextEvent(for: &parser, is: .scalar("in-line value"))
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .emptyScalar)
        assertNextEvent(for: &parser, is: .scalar("quoted key"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("entry"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_19_CompactBlockMappings() {
        var parser = makeParser(for: example_8_19)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("sun"))
        assertNextEvent(for: &parser, is: .scalar("yellow"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("earth"))
        assertNextEvent(for: &parser, is: .scalar("blue"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("moon"))
        assertNextEvent(for: &parser, is: .scalar("white"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_20_BlockNodeTypes() {
        var parser = makeParser(for: example_8_20)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("flow in block"))
        assertNextEvent(for: &parser, is: .scalar("Block scalar\n"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block, tag: "tag:yaml.org,2002:map"))
        assertNextEvent(for: &parser, is: .scalar("foo"))
        assertNextEvent(for: &parser, is: .scalar("bar"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_21_BlockScalarNodes() {
        var parser = makeParser(for: example_8_21)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("literal"))
        assertNextEvent(for: &parser, is: .scalar("value\n"))
        assertNextEvent(for: &parser, is: .scalar("folded"))
        assertNextEvent(for: &parser, is: .scalar("value", tag: "!foo"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }

    func testExample_8_22_BlockCollectionNodes() {
        var parser = makeParser(for: example_8_22)
        assertNextEvent(for: &parser, is: .documentStart)
        assertNextEvent(for: &parser, is: .mappingStart(style: .block))
        assertNextEvent(for: &parser, is: .scalar("sequence"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block, tag: "tag:yaml.org,2002:seq"))
        assertNextEvent(for: &parser, is: .scalar("entry"))
        assertNextEvent(for: &parser, is: .sequenceStart(style: .block, tag: "tag:yaml.org,2002:seq"))
        assertNextEvent(for: &parser, is: .scalar("nested"))
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .sequenceEnd)
        assertNextEvent(for: &parser, is: .scalar("mapping"))
        assertNextEvent(for: &parser, is: .mappingStart(style: .block, tag: "tag:yaml.org,2002:map"))
        assertNextEvent(for: &parser, is: .scalar("foo"))
        assertNextEvent(for: &parser, is: .scalar("bar"))
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .mappingEnd)
        assertNextEvent(for: &parser, is: .documentEnd)
    }


}

class ParserUTF8DataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf8

    func makeReader(for data: Data) -> YAML.Reader {
        return ContiguousReader<UTF8>(data: data)
    }

}

class ParserUTF16LEDataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf16LittleEndian

    func makeReader(for data: Data) -> Reader {
        return ContiguousReader<UTF16LE>(data: data)
    }

}

class ParserUTF16BEDataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf16BigEndian

    func makeReader(for data: Data) -> Reader {
        return ContiguousReader<UTF16BE>(data: data)
    }

}

class ParserUTF32LEDataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf32LittleEndian

    func makeReader(for data: Data) -> Reader {
        return ContiguousReader<UTF32LE>(data: data)
    }

}

class ParserUTF32BEDataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf32BigEndian

    func makeReader(for data: Data) -> Reader {
        return ContiguousReader<UTF32BE>(data: data)
    }

}

class ParserAutoUTF8DataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf8

    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }

}

class ParserAutoUTF16DataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf16

    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }

}

class ParserAutoUTF16LEDataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf16LittleEndian

    func makeReader(for data: Data) -> YAML.Reader {

        return AutoContiguousReader(data: data)
    }

}

class ParserAutoUTF16BEDataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf16BigEndian

    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }

}

class ParserAutoUTF32DataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf32

    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }

}

class ParserAutoUTF32LEDataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf32LittleEndian

    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }

}

class ParserAutoUTF32BEDataTests: ParserStringTests, ParserDataTests {

    let stringEncoding = String.Encoding.utf32BigEndian

    func makeReader(for data: Data) -> YAML.Reader {
        return AutoContiguousReader(data: data)
    }

}
