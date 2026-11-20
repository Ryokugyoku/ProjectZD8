import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICCSVTokenizer` の区切りの規則 R1〜R5(引用・引用なし・改行・空行・終端)を検証します。
@MainActor
final class JARTICCSVTokenizerTests: XCTestCase {
    /// R1: 引用付きの項目は、中の `,` と `""`(`"` 1文字)を保って1項目になります。
    func testQuotedFieldKeepsCommaAndDoubledQuote() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings("\"a,b\",\"c\"\"d\",e\r\n"), [["a,b", "c\"d", "e"]])
    }

    /// R1: 空の引用付き項目は空の項目になります。
    func testEmptyQuotedFieldIsEmptyField() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings("\"\",x\r\n"), [["", "x"]])
    }

    /// R1: 項目内の CRLF と LF は、そのまま保たれます。
    func testQuotedFieldKeepsEmbeddedLineBreaks() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings("\"a\r\nb\",\"c\nd\",e\r\n"), [["a\r\nb", "c\nd", "e"]])
    }

    /// R1: 引用の後に区切りでないバイトが続いたら、`,` か LF までをそのまま足します(寛容)。
    func testBytesAfterClosingQuoteAreAppendedUntilDelimiter() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings("\"ab\"cd,e\r\n"), [["abcd", "e"]])
    }

    /// R1: 全項目が引用された行(実データの形)を、項目数どおりに区切ります。
    func testFullyQuotedRowMatchesFieldCount() throws {
        let rows = try TestJARTICCSVRun.strings("\"k_2.1\",\"13\",\"\",\"x y\"\r\n")
        XCTAssertEqual(rows, [["k_2.1", "13", "", "x y"]])
    }

    /// R2: 引用なしの項目の途中の `"` は、そのまま足します。
    func testQuoteInsideUnquotedFieldIsLiteral() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings("a\"b,c\"\r\n"), [["a\"b", "c\""]])
    }

    /// R3: CR+LF でも LF だけでも行が終わり、直前の CR は項目へ入りません。
    func testCRLFAndLFBothEndRowsAndCarriageReturnIsDropped() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings("a,b\r\nc,d\ne,f\r\n"), [["a", "b"], ["c", "d"], ["e", "f"]])
    }

    /// R3: 引用付き項目の直後の CR+LF でも、CR は項目へ入りません。
    func testCarriageReturnAfterQuotedFieldIsDropped() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings("\"a\",\"b\"\r\n\"c\",\"d\"\r\n"), [["a", "b"], ["c", "d"]])
    }

    /// R3: LF が続かない CR は、項目内のバイトとして残ります。
    func testLoneCarriageReturnInsideFieldIsKept() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings("a\rb,c\n"), [["a\rb", "c"]])
    }

    /// R4: 空行(CR+LF だけ・LF だけ)は出力しません。
    func testBlankLinesAreSkipped() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings("\r\na\r\n\n\r\nb\n\n"), [["a"], ["b"]])
    }

    /// R4: 区切りだけの行(空の項目が2つ)は空行ではなく、項目数2の行です。
    func testRowOfOnlyDelimitersIsNotBlank() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings(",\r\n"), [["", ""]])
        XCTAssertEqual(try TestJARTICCSVRun.strings(",,\n"), [["", "", ""]])
    }

    /// R5: 末尾に改行のない最後の行も出力します。
    func testLastRowWithoutLineBreakIsEmitted() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings("a,b\r\nc,d"), [["a", "b"], ["c", "d"]])
        XCTAssertEqual(try TestJARTICCSVRun.strings("\"x\",\"y\""), [["x", "y"]])
    }

    /// R5: 最後の改行の後に行を重ねて出さず、空の入力は行を出しません。
    func testNoExtraRowAfterFinalLineBreakAndEmptyInput() throws {
        XCTAssertEqual(try TestJARTICCSVRun.strings("a\r\n"), [["a"]])
        XCTAssertEqual(try TestJARTICCSVRun.strings(""), [])
    }

    /// R5: 引用の途中でファイルが終わったら `unterminatedQuote` です。
    func testEndInsideQuoteThrowsUnterminatedQuote() {
        for text in ["\"abc", "a,\"b\r\nc", "\"a\"\"", "\"a\r"] {
            XCTAssertThrowsError(try TestJARTICCSVRun.strings(text), text) {
                XCTAssertEqual($0 as? JARTICCSVError, .unterminatedQuote, text)
            }
        }
    }
}
