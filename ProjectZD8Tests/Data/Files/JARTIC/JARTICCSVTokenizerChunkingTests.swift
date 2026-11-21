import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICCSVTokenizer` の結果が、チャンクの境目(引用・`""`・CR+LF・Shift-JIS の2バイト文字の途中を含む全位置)に依存しないことを検証します。
@MainActor
final class JARTICCSVTokenizerChunkingTests: XCTestCase {
    /// 引用・`""`・項目内の CRLF・引用の後の余分なバイト・空行・改行なしの最終行を含む入力です。
    private let sample = Array((
        "\"a,b\",\"c\"\"d\",e\r\n" + "\"multi\r\nline\",x\"y,z\r\n" + "\r\n" + "\"q\"r,s\n" + "last,row"
    ).utf8)

    /// 仕様から手で決めた、`sample` の期待する行です。
    private let expectedSample: [[String]] = [
        ["a,b", "c\"d", "e"], ["multi\r\nline", "x\"y", "z"], ["qr", "s"], ["last", "row"]
    ]

    /// 責務: 項目のバイト列を UTF-8 の文字列へ直します。
    private func strings(_ rows: [TestJARTICCSVRun.Fields]) -> [[String]] {
        rows.map { $0.map { String(decoding: $0, as: UTF8.self) } }
    }

    /// 一括で与えた結果が、仕様から決めた期待値と一致します(以降の比較の基準)。
    func testWholeInputMatchesSpecExpectation() throws {
        XCTAssertEqual(strings(try TestJARTICCSVRun.rows(sample)), expectedSample)
    }

    /// 2つの塊への分け方を、全ての位置(1バイトずつずらした全通り)で試しても結果が同じです。
    func testEverySingleSplitPositionGivesSameRows() throws {
        for position in 0...sample.count {
            let rows = try TestJARTICCSVRun.rows(sample, splitAt: [position])
            XCTAssertEqual(strings(rows), expectedSample, "位置 \(position)")
        }
    }

    /// 1バイトずつ与えても結果が同じです。
    func testByteByByteGivesSameRows() throws {
        XCTAssertEqual(strings(try TestJARTICCSVRun.rowsByteByByte(sample)), expectedSample)
    }

    /// 3つの塊への分け方を、小さな入力の全通りで試しても結果が同じです。
    func testEveryTwoSplitPositionsGiveSameRows() throws {
        let small = Array("\"a\"\"b\",\"c\r\nd\"\r\ne,\"\"\r\n".utf8)
        let expected = [["a\"b", "c\r\nd"], ["e", ""]]
        for first in 0...small.count {
            for second in first...small.count {
                let rows = try TestJARTICCSVRun.rows(small, splitAt: [first, second])
                XCTAssertEqual(strings(rows), expected, "位置 \(first), \(second)")
            }
        }
    }

    /// CR+LF の CR と LF の間で切っても、CR は項目へ入らず、行は1つだけ出ます。
    func testSplitBetweenCarriageReturnAndLineFeed() throws {
        let bytes = Array("a,b\r\nc,d\r\n".utf8)
        let rows = try TestJARTICCSVRun.rows(bytes, splitAt: [4])
        XCTAssertEqual(strings(rows), [["a", "b"], ["c", "d"]])
    }

    /// 引用の途中・`""` の途中で切っても結果が変わらず、途中で終われば `unterminatedQuote` です。
    func testSplitInsideEscapedQuoteAndUnterminatedAtEnd() throws {
        let bytes = Array("\"a\"\"b\"\r\n".utf8)
        for position in 0...bytes.count {
            XCTAssertEqual(strings(try TestJARTICCSVRun.rows(bytes, splitAt: [position])), [["a\"b"]], "位置 \(position)")
        }
        XCTAssertThrowsError(try TestJARTICCSVRun.rows(Array("\"a\"\"".utf8), splitAt: [3])) {
            XCTAssertEqual($0 as? JARTICCSVError, .unterminatedQuote)
        }
    }
}
