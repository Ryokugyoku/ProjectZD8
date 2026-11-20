import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICCSVRow` の項目の取り出し(`fieldCount`・`field`・`asciiString`・`isBlank`)を検証します。行は区切り器から作ります。
@MainActor
final class JARTICCSVRowTests: XCTestCase {
    /// 責務: 1行の CSV を区切り器で行にして返します。
    private func row(_ bytes: [UInt8]) throws -> JARTICCSVRow {
        var tokenizer = JARTICCSVTokenizer()
        var rows: [JARTICCSVRow] = []
        try bytes.withUnsafeBytes { try tokenizer.consume($0, emit: { rows.append($0) }) }
        try tokenizer.finish(emit: { rows.append($0) })
        return try XCTUnwrap(rows.first)
    }

    /// 項目数と各項目のバイト列が、区切りの通りです(空の項目を含む)。
    func testFieldCountAndFieldBytes() throws {
        let row = try row(Array("ab,,cde\r\n".utf8))

        XCTAssertEqual(row.fieldCount, 3)
        XCTAssertEqual(Array(row.field(0)), Array("ab".utf8))
        XCTAssertEqual(Array(row.field(1)), [])
        XCTAssertEqual(Array(row.field(2)), Array("cde".utf8))
    }

    /// `asciiString` は ASCII の項目を文字列にし、前後の空白を除きます。
    func testASCIIStringTrimsSurroundingSpaces() throws {
        let row = try row(Array("abc,  12.5 ,\" x y \"\r\n".utf8))

        XCTAssertEqual(row.asciiString(0), "abc")
        XCTAssertEqual(row.asciiString(1), "12.5")
        XCTAssertEqual(row.asciiString(2), "x y")
    }

    /// `asciiString` は ASCII 以外のバイトを含む項目では `nil` です(Shift-JIS の漢字・0x80 以上)。
    func testASCIIStringIsNilForNonASCII() throws {
        let sjis = try XCTUnwrap("表".data(using: .shiftJIS))
        let row = try row(Array("a".utf8) + [0x2C] + Array(sjis) + [0x2C, 0x61, 0x80, 0x0A])

        XCTAssertEqual(row.asciiString(0), "a")
        XCTAssertNil(row.asciiString(1))
        XCTAssertNil(row.asciiString(2))
    }

    /// `isBlank` は空の項目で真、中身のある項目で偽です。
    func testIsBlankForEmptyAndNonEmptyFields() throws {
        let row = try row(Array("x,,\"\",0,表\r\n".utf8))

        XCTAssertFalse(row.isBlank(0))
        XCTAssertTrue(row.isBlank(1))
        XCTAssertTrue(row.isBlank(2))
        XCTAssertFalse(row.isBlank(3))
        XCTAssertFalse(row.isBlank(4))
    }
}
