import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICCSVHeader` が、Shift-JIS の見出し行から列番号を引き、必須の列の欠落を `missingColumn` で報告することを検証します。
@MainActor
final class JARTICCSVHeaderTests: XCTestCase {
    /// 責務: 見出しの名前の並びを、Shift-JIS・カンマ区切りの1行にして、区切り器で行にします。
    private func headerRow(_ names: [String], file: StaticString = #filePath, line: UInt = #line) throws -> JARTICCSVRow {
        var bytes: [UInt8] = []
        for (index, name) in names.enumerated() {
            let encoded = try XCTUnwrap(name.data(using: .shiftJIS), "Shift-JIS へ変換できません: \(name)", file: file, line: line)
            bytes += (index == 0 ? [] : [0x2C]) + Array(encoded)
        }
        bytes += [0x0D, 0x0A]
        return try firstRow(bytes)
    }

    /// 責務: バイト列を区切り器へ与え、最初の行を返します。
    private func firstRow(_ bytes: [UInt8]) throws -> JARTICCSVRow {
        var tokenizer = JARTICCSVTokenizer()
        var rows: [JARTICCSVRow] = []
        try bytes.withUnsafeBytes { try tokenizer.consume($0, emit: { rows.append($0) }) }
        try tokenizer.finish(emit: { rows.append($0) })
        return try XCTUnwrap(rows.first)
    }

    /// 必須の列に、実データと同様の埋め草の列を足して、指定の位置へ並べた名前の列です。
    private func names(padding: Int = 67, reversed: Bool = false) -> [String] {
        let all = JARTICColumnName.required + (0..<padding).map { "予備列\($0)" }
        return reversed ? all.reversed() : all
    }

    /// 必須の列の名前が、全て Shift-JIS で表せる(見出しの照合に使える)ことと、数が 13 + 90 = 103 個であることを確かめます。
    func testRequiredNamesAreDistinctAndEncodable() {
        let required = JARTICColumnName.required
        XCTAssertEqual(required.count, 103)
        XCTAssertEqual(Set(required).count, 103)
        for name in required {
            XCTAssertNotNil(name.data(using: .shiftJIS), name)
        }
    }

    /// 全ての必須の列について、Shift-JIS の見出しから列番号を引けます。
    func testIndexLookupForEveryRequiredColumn() throws {
        let columns = names()
        let header = try JARTICCSVHeader(row: try headerRow(columns))

        XCTAssertEqual(header.fieldCount, columns.count)
        for (index, name) in columns.enumerated() {
            XCTAssertEqual(header.index(of: name), index, name)
        }
    }

    /// 列の順序が変わっても(逆順でも)、名前で列番号を引けます。
    func testIndexLookupFollowsColumnOrder() throws {
        let columns = names(reversed: true)
        let header = try JARTICCSVHeader(row: try headerRow(columns))

        XCTAssertEqual(header.index(of: JARTICColumnName.uniqueKey), columns.firstIndex(of: JARTICColumnName.uniqueKey))
        XCTAssertEqual(header.index(of: JARTICColumnName.formatVersion), columns.count - 1)
    }

    /// 必須の列が1つ欠けると、欠けた名前つきの `missingColumn` です(103個のそれぞれで)。
    func testMissingAnyRequiredColumnThrowsMissingColumnWithItsName() throws {
        for missing in JARTICColumnName.required {
            let row = try headerRow(names().filter { $0 != missing })

            XCTAssertThrowsError(try JARTICCSVHeader(row: row), missing) {
                XCTAssertEqual($0 as? JARTICArchiveFormatError, .missingColumn(missing), missing)
            }
        }
    }

    /// 必須でない列が足りなくても、必須が揃っていれば読めます(列数は行の項目数のとおり)。
    func testOnlyRequiredColumnsAreEnoughAndFieldCountFollowsRow() throws {
        let header = try JARTICCSVHeader(row: try headerRow(names(padding: 0)))
        XCTAssertEqual(header.fieldCount, 103)

        let wide = try JARTICCSVHeader(row: try headerRow(names(padding: 300)))
        XCTAssertEqual(wide.fieldCount, 403)
    }

    /// 見出しに無い名前の `index(of:)` は `nil` です。
    func testUnknownNameHasNoIndex() throws {
        let header = try JARTICCSVHeader(row: try headerRow(names()))
        XCTAssertNil(header.index(of: "存在しない列"))
        XCTAssertNil(header.index(of: ""))
    }

    /// 全角括弧の名前は、半角括弧の見出しとは一致しません(見出しは半角の括弧です)。
    func testHalfWidthParenthesesMatchAndFullWidthDoNot() throws {
        let header = try JARTICCSVHeader(row: try headerRow(names()))

        XCTAssertNotNil(header.index(of: "進入方向(座標)"))
        XCTAssertNil(header.index(of: "進入方向（座標）"))
    }

    /// Shift-JIS として復号できない見出しは `headerNotDecodable` です。
    func testUndecodableHeaderThrowsHeaderNotDecodable() throws {
        for invalid: [UInt8] in [[0xFF, 0xFF], [0x83], [0x81, 0x20]] {
            var bytes = try XCTUnwrap(names().joined(separator: ",").data(using: .shiftJIS)).map { $0 }
            bytes += [0x2C] + invalid + [0x0D, 0x0A]
            let row = try firstRow(bytes)

            XCTAssertThrowsError(try JARTICCSVHeader(row: row), "\(invalid)") {
                XCTAssertEqual($0 as? JARTICArchiveFormatError, .headerNotDecodable, "\(invalid)")
            }
        }
    }
}
