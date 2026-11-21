import Foundation
import XCTest
@testable import ProjectZD8

/// Shift-JIS の2バイト文字(2バイト目が `\` など ASCII の範囲に入る文字)を含む項目を、`JARTICCSVTokenizer` が区切りを誤認せず1項目として取ることを検証します。
@MainActor
final class JARTICCSVTokenizerShiftJISTests: XCTestCase {
    /// 2バイト目が 0x5C になる文字です。
    private let backslashSecondByte = "表ソ能十申予構暴貼"

    /// 責務: 文字列を Shift-JIS のバイト列にします。
    private func shiftJIS(_ text: String) throws -> [UInt8] {
        Array(try XCTUnwrap(text.data(using: .shiftJIS), "Shift-JIS へ変換できません: \(text)"))
    }

    /// テストの前提: 選んだ文字の2バイト目が 0x5C(ASCII の `\`)であること。
    func testPremiseSecondBytesAreBackslash() throws {
        for character in backslashSecondByte {
            let bytes = try shiftJIS(String(character))
            XCTAssertEqual(bytes.count, 2, "\(character)")
            XCTAssertEqual(bytes.last, 0x5C, "\(character)")
        }
    }

    /// 2バイト目が `\` の文字を含む項目が、1項目のまま取れます。
    func testFieldsWithBackslashSecondByteStayWhole() throws {
        let bytes = try shiftJIS("表,ソ,能\r\n") + (try shiftJIS("十申予,構暴貼\r\n"))

        let rows = try TestJARTICCSVRun.rows(bytes)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], [try shiftJIS("表"), try shiftJIS("ソ"), try shiftJIS("能")])
        XCTAssertEqual(rows[1], [try shiftJIS("十申予"), try shiftJIS("構暴貼")])
    }

    /// 引用付きでも、2バイト文字の後ろの `"` と `,` を区切りとして正しく扱います。
    func testQuotedFieldsWithTwoByteCharacters() throws {
        let bytes = try shiftJIS("\"表\",\"ソ,能\",\"十\"\"申\"\r\n")

        let rows = try TestJARTICCSVRun.rows(bytes)

        XCTAssertEqual(rows, [[try shiftJIS("表"), try shiftJIS("ソ,能"), try shiftJIS("十\"申")]])
    }

    /// 2バイト文字の途中(先頭バイトの直後)を含む全位置で切っても、結果が同じです。
    func testEverySplitPositionInsideTwoByteCharactersGivesSameRows() throws {
        let bytes = try shiftJIS("\"表ソ\",能,\"十\"\"申\"\r\n予構,暴貼")
        let expected = try TestJARTICCSVRun.rows(bytes)
        XCTAssertEqual(expected, [
            [try shiftJIS("表ソ"), try shiftJIS("能"), try shiftJIS("十\"申")],
            [try shiftJIS("予構"), try shiftJIS("暴貼")]
        ])

        for position in 0...bytes.count {
            XCTAssertEqual(try TestJARTICCSVRun.rows(bytes, splitAt: [position]), expected, "位置 \(position)")
        }
        XCTAssertEqual(try TestJARTICCSVRun.rowsByteByByte(bytes), expected)
    }

    /// 項目のバイト列を Shift-JIS で復号すると、元の文字列に戻ります。
    func testFieldBytesDecodeBackToOriginalText() throws {
        let rows = try TestJARTICCSVRun.rows(try shiftJIS("沖縄県警,表\r\n"))
        let decoded = rows[0].map { String(bytes: $0, encoding: .shiftJIS) }
        XCTAssertEqual(decoded, ["沖縄県警", "表"])
    }
}
