import Foundation
import XCTest
@testable import ProjectZD8

/// `JARTICOpenDataIndexDecoder` が配布の一覧 JSON を仕様どおりに解読し、採用できない行を捨てることを検証します。
@MainActor
final class JARTICOpenDataIndexDecoderTests: XCTestCase {
    private typealias Builder = JARTICIndexJSONBuilder
    private let decoder = JARTICOpenDataIndexDecoder()

    /// 都道府県コードを作ります。
    private func prefecture(_ number: Int) throws -> JapanesePrefectureCode {
        try XCTUnwrap(JapanesePrefectureCode(number))
    }

    /// 実際の JSON と同じ形の見本を解読すると、47件・群馬の綴り・公開の印・基準月が取れます。
    ///
    /// 責務: 件数、`gumma`、`202611010000`、2026-09 を確認します。
    func testRealisticIndexYields47EntriesWithGummaStampAndMonth() throws {
        let catalog = try decoder.decode(Builder.realisticIndex())

        XCTAssertEqual(catalog.entries.count, 47)
        XCTAssertEqual(catalog.dataMonth, RoadRegulationDataMonth(year: 2026, month: 9))
        let gumma = try XCTUnwrap(catalog.entry(for: try prefecture(10)))
        XCTAssertEqual(gumma.archiveURL.absoluteString, "https://www.jartic.or.jp/d/opendata/202611010000/typeD_gumma.zip")
        XCTAssertEqual(gumma.publicationStamp, "202611010000")
    }

    /// `R01`〜`R47` が都道府県コード 1〜47 に対応し、リンクが相対パスから連結されます。
    ///
    /// 責務: 全47件で、コードごとの URL・公開の印・https・クエリなしを確認します。
    func testEveryPrefectureMapsToItsOwnLink() throws {
        let catalog = try decoder.decode(Builder.realisticIndex())

        for number in 1...47 {
            let entry = try XCTUnwrap(catalog.entry(for: try prefecture(number)), "R\(number)")
            let expected = "https://www.jartic.or.jp/d/opendata/202611010000/typeD_\(Builder.slug(for: number)).zip"
            XCTAssertEqual(entry.archiveURL.absoluteString, expected)
            XCTAssertEqual(entry.prefecture, try prefecture(number))
            XCTAssertNil(entry.archiveURL.query)
        }
    }

    /// typeD だけを採ります(typeB は採らない)。
    ///
    /// 責務: typeB が先にあっても、すべての URL が typeD のものであることを確認します。
    func testOnlyTypeDIsAdopted() throws {
        let catalog = try decoder.decode(Builder.realisticIndex())

        XCTAssertTrue(catalog.entries.allSatisfy { $0.archiveURL.lastPathComponent.hasPrefix("typeD_") })
    }

    /// typeD が無い・JSON が読めない・形が違う場合は `catalogFormatChanged` です。
    ///
    /// 責務: 7種類の想定外の入力がすべて同じエラーになることを確認します。
    func testUnexpectedShapesThrowCatalogFormatChanged() {
        let onlyTypeB = Builder.data([Builder.section(type: "typeB", rows: Builder.fullRows())])
        let noList = Builder.data([["type": "typeD", "targetMonth": "2026年09月"]])
        let emptyList = Builder.data([Builder.section(type: "typeD", rows: [])])
        let object = Data(#"{"type":"typeD"}"#.utf8)
        let inputs: [Data] = [onlyTypeB, noList, emptyList, object, Data("[]".utf8), Data("not json".utf8), Data()]

        for input in inputs {
            XCTAssertThrowsError(try decoder.decode(input)) {
                XCTAssertEqual($0 as? RoadRegulationImportError, .catalogFormatChanged)
            }
        }
    }

    /// 有効な行が1つも無ければ `catalogFormatChanged` です。
    ///
    /// 責務: id もリンクも欠けた行だけの一覧が失敗になることを確認します。
    func testAllRowsInvalidThrowsCatalogFormatChanged() {
        let rows = [Builder.Row(id: nil, link: "/202611010000/typeD_a.zip"), Builder.Row(id: "R01", link: nil)]

        XCTAssertThrowsError(try decoder.decode(Builder.data([Builder.section(type: "typeD", rows: rows)]))) {
            XCTAssertEqual($0 as? RoadRegulationImportError, .catalogFormatChanged)
        }
    }

    /// 危険なリンクの行は捨てます。
    ///
    /// 責務: 親ディレクトリ・他のホスト・http・クエリ・別種別・桁違いなどの行が採用されないことを確認します。
    func testUnsafeOrMalformedLinksAreDropped() throws {
        let badLinks = [
            "/x/../evil.zip", "https://other.example/202611010000/typeD_a.zip", "http://www.jartic.or.jp/d/opendata/202611010000/typeD_a.zip",
            "//evil.example/202611010000/typeD_a.zip", "/202611010000/typeD_a.zip?x=1", "/202611010000/../typeD_a.zip",
            "/20261101000/typeD_a.zip", "/2026110100000/typeD_a.zip", "/202611010000/typeB_a.zip", "/202611010000/typeD_a.zip.exe",
            "/202611010000/typeD_A.zip", "/202611010000/typeD_.zip", "/202611010000/typeD_a.zip#frag", "/202611010000/sub/typeD_a.zip", ""
        ]
        var rows = [Builder.validRow(1)]
        for (offset, link) in badLinks.enumerated() {
            rows.append(Builder.Row(id: String(format: "R%02d", offset + 2), link: link))
        }

        let catalog = try decoder.decode(Builder.data([Builder.section(type: "typeD", rows: rows)]))

        XCTAssertEqual(catalog.entries.map(\.prefecture), [try prefecture(1)])
    }

    /// `R48`・`R00` などの id の行は捨てます。
    ///
    /// 責務: 範囲外・書式違い・全角数字の id が採用されないことを確認します。
    func testOutOfRangeAndMalformedIdsAreDropped() throws {
        let ids = ["R48", "R00", "r02", "R3", "R004", "05", "RA6", "R０7", ""]
        var rows = [Builder.validRow(1)]
        rows += ids.map { Builder.Row(id: $0, link: "/202611010000/typeD_zzz.zip") }

        let catalog = try decoder.decode(Builder.data([Builder.section(type: "typeD", rows: rows)]))

        XCTAssertEqual(catalog.entries.map(\.prefecture), [try prefecture(1)])
    }

    /// 47件でなくても、有効な行だけを採用します。
    ///
    /// 責務: 46件の一覧で欠けた県が `nil` になることを確認します。
    func testPartialListKeepsValidRowsOnly() throws {
        let rows = Builder.fullRows().filter { $0.id != "R13" }

        let catalog = try decoder.decode(Builder.realisticIndex(typeDRows: rows))

        XCTAssertEqual(catalog.entries.count, 46)
        XCTAssertNil(catalog.entry(for: try prefecture(13)))
        XCTAssertNotNil(catalog.entry(for: try prefecture(14)))
    }

    /// 基準月は読めた時だけ入り、読めなくても一覧は失敗にしません。
    ///
    /// 責務: 正常・境界の月と、欠落・書式違い・範囲外・数値型の基準月を確認します。
    func testDataMonthParsingAndTolerance() throws {
        let rows = [Builder.validRow(1)]
        func month(_ value: Any?) throws -> RoadRegulationDataMonth? {
            try decoder.decode(Builder.data([Builder.section(type: "typeD", targetMonth: value, rows: rows)])).dataMonth
        }

        XCTAssertEqual(try month("2026年12月"), RoadRegulationDataMonth(year: 2026, month: 12))
        XCTAssertEqual(try month("2000年01月"), RoadRegulationDataMonth(year: 2000, month: 1))
        for bad: Any? in [nil, "2026-09", "2026年13月", "2026年00月", "26年09月", "2026年9月", "", 202609] {
            XCTAssertNil(try month(bad), "\(String(describing: bad))")
        }
    }

    /// 指定した配布の基点が連結に使われ、その配下でないリンクは採用しません。
    ///
    /// 責務: 基点を差し替えた解読器の URL を確認します。
    func testCustomDownloadBaseURLIsUsed() throws {
        let base = try XCTUnwrap(URL(string: "https://example.test/files"))
        let custom = JARTICOpenDataIndexDecoder(downloadBaseURL: base)

        let catalog = try custom.decode(Builder.realisticIndex())

        let entry = try XCTUnwrap(catalog.entry(for: try prefecture(1)))
        XCTAssertEqual(entry.archiveURL.absoluteString, "https://example.test/files/202611010000/typeD_\(Builder.slug(for: 1)).zip")
        XCTAssertEqual(entry.archiveURL.host, "example.test")
    }

    /// 一覧に無い県は `nil` です。
    ///
    /// 責務: `entry(for:)` が欠けた県で `nil` を返すことを確認します。
    func testEntryForMissingPrefectureIsNil() throws {
        let catalog = try decoder.decode(Builder.data([Builder.section(type: "typeD", rows: [Builder.validRow(5)])]))

        XCTAssertNil(catalog.entry(for: try prefecture(6)))
        XCTAssertNotNil(catalog.entry(for: try prefecture(5)))
    }
}
