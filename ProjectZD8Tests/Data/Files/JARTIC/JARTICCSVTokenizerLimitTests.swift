import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICCSVTokenizer` の行の最大長(R6)を検証します。
@MainActor
final class JARTICCSVTokenizerLimitTests: XCTestCase {
    /// 責務: 上限を超えた時に `rowTooLong` で止まることを確かめます。
    private func assertRowTooLong(_ chunks: [[UInt8]], limit: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try TestJARTICCSVRun.rows(chunks: chunks, maximumRowBytes: limit), file: file, line: line) {
            XCTAssertEqual($0 as? JARTICCSVError, .rowTooLong, file: file, line: line)
        }
    }

    /// 上限を超える1行は、改行がなくても `rowTooLong` で止まります。
    func testRowOverLimitWithoutLineBreakIsTooLong() {
        assertRowTooLong([[UInt8](repeating: 0x61, count: 100)], limit: 16)
        assertRowTooLong(Array(repeating: [UInt8](repeating: 0x61, count: 10), count: 10), limit: 16)
    }

    /// 上限を超える行は、改行で終わっていても `rowTooLong` です。
    func testTerminatedRowOverLimitIsTooLong() {
        assertRowTooLong([Array((String(repeating: "a", count: 100) + "\r\n").utf8)], limit: 16)
    }

    /// 引用付き項目の中で上限を超えても `rowTooLong` です(改行を含む複数行の項目も1行として数えます)。
    func testQuotedFieldOverLimitIsTooLong() {
        assertRowTooLong([Array(("\"" + String(repeating: "a\r\n", count: 50) + "\"\r\n").utf8)], limit: 16)
    }

    /// 上限内の短い行なら、合計が上限を超えても(行ごとに数えるので)読めます。
    func testManyShortRowsBeyondLimitAreAccepted() throws {
        let text = String(repeating: "ab,cd\r\n", count: 50)
        let rows = try TestJARTICCSVRun.strings(text)
        XCTAssertEqual(rows.count, 50)
        XCTAssertEqual(try TestJARTICCSVRun.rows(Array(text.utf8), maximumRowBytes: 16).count, 50)
    }

    /// 既定の上限は 4 MiB です: 1 MiB の行は読め、4 MiB を超える行は `rowTooLong` です。
    func testDefaultLimitIsFourMebibytes() throws {
        let chunk = [UInt8](repeating: 0x61, count: 65_536)
        let accepted = Array(repeating: chunk, count: 16) + [Array("\r\n".utf8)]
        XCTAssertEqual(try TestJARTICCSVRun.rows(chunks: accepted).first?.first?.count, 16 * 65_536)

        let tooLong = Array(repeating: chunk, count: 65) + [Array("\r\n".utf8)]
        XCTAssertThrowsError(try TestJARTICCSVRun.rows(chunks: tooLong)) {
            XCTAssertEqual($0 as? JARTICCSVError, .rowTooLong)
        }
    }
}
