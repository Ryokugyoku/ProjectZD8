import Foundation
import XCTest
@testable import ProjectZD8

/// 出典の表示(使用した版の行・利用日・配布ページ)を作る規則を検証します(設計書 §3.3、§3.4 Attribution、§7 TC1a)。
///
/// 書式は固定の表から解決し、都道府県名はキーを `<キー>` に包んで返すため、言語設定に依存しません。
@MainActor
final class SessionRoadRegulationReviewAttributionBuilderTests: XCTestCase {
    /// 値の短い名前です。
    private typealias Values = SessionRoadRegulationReviewTestValues
    /// 版の行の書式です。
    private static let datasetFormat = "%1$@ (%2$@)"
    /// 利用日の書式です。
    private static let usedOnFormat = "U:%@"
    /// 2026-11-20 16:00:00 UTC(2026-11-21 01:00:00 JST)です。
    private let usedOn = Date(timeIntervalSince1970: 1_795_190_400)

    /// 書式の表で文言を解決する検証対象を作ります。
    ///
    /// 責務: 版・基準月・利用日の書式を表から返し、それ以外のキーは `<キー>` に包む builder を返します。
    /// - Parameters:
    ///   - monthFormat: 基準月の書式。
    ///   - locale: ロケール識別子。
    ///   - timeZone: タイムゾーン。省くと日本時間。
    /// - Returns: builder。
    private func builder(
        monthFormat: String = "%1$lld/%2$lld",
        locale: String = "ja_JP",
        timeZone: TimeZone = SessionRoadRegulationReviewTestValues.tokyo
    ) -> SessionRoadRegulationReviewAttributionBuilder {
        let table: [String: String] = [
            "analysis.road_regulation.attribution.dataset": Self.datasetFormat,
            "analysis.road_regulation.attribution.data_month": monthFormat,
            "road_regulation.attribution.used_on": Self.usedOnFormat
        ]
        return SessionRoadRegulationReviewAttributionBuilder(
            locale: Locale(identifier: locale),
            timeZone: timeZone,
            localize: { table[$0] ?? "<\($0)>" }
        )
    }

    /// 版の行の期待値を作ります。
    ///
    /// 責務: 県名のキーと基準月の文字列を版の書式に入れた文字列を返します。
    /// - Parameters:
    ///   - code: 2桁の都道府県コード。
    ///   - month: 基準月の文字列。
    /// - Returns: 期待値。
    private func line(_ code: String, _ month: String) -> String {
        "<road_regulation.prefecture.\(code)> (\(month))"
    }

    /// 責務: 版の行を都道府県コードの昇順に並べ、県名のキーを2桁(1 → 01、13、47)にすることを確かめます。
    func testSortsByPrefectureCodeWithTwoDigitKeys() {
        let review = Values.review(datasets: [Values.reference(47, 2026, 9), Values.reference(1, 2026, 8), Values.reference(13, 2026, 7)])

        let texts = builder().attribution(for: review).datasetTexts

        XCTAssertEqual(texts, [line("01", "2026/8"), line("13", "2026/7"), line("47", "2026/9")])
    }

    /// 責務: 同じ県の版は基準月の昇順(年をまたぐ順を含む)に並べることを確かめます。
    func testSamePrefectureSortsByDataMonth() {
        let review = Values.review(datasets: [Values.reference(47, 2026, 9), Values.reference(47, 2025, 12), Values.reference(47, 2026, 1)])

        let texts = builder().attribution(for: review).datasetTexts

        XCTAssertEqual(texts, [line("47", "2025/12"), line("47", "2026/1"), line("47", "2026/9")])
    }

    /// 責務: 同じ県・同じ基準月の重複は1つにまとめ、月の違う版は残すことを確かめます。
    func testDuplicatesAreMerged() {
        let review = Values.review(datasets: [Values.reference(47, 2026, 9), Values.reference(47, 2026, 9), Values.reference(47, 2026, 8)])

        let texts = builder().attribution(for: review).datasetTexts

        XCTAssertEqual(texts, [line("47", "2026/8"), line("47", "2026/9")])
    }

    /// 責務: 基準月の書式に年・月の順で値を渡す(位置指定 `%2$lld/%1$lld` なら「9/2026」)ことを確かめます。
    func testDataMonthArgumentsAreYearThenMonth() {
        let review = Values.review(datasets: [Values.reference(47, 2026, 9)])

        let texts = builder(monthFormat: "%2$lld/%1$lld").attribution(for: review).datasetTexts

        XCTAssertEqual(texts, [line("47", "9/2026")])
    }

    /// 責務: 版が空なら、版の行も空であることを確かめます。
    func testEmptyDatasetsGiveNoLines() {
        XCTAssertEqual(builder().attribution(for: Values.review(datasets: [])).datasetTexts, [])
    }

    /// 責務: 利用日が nil なら、利用日の文字列も nil であることを確かめます。
    func testNilUsedOnGivesNilText() {
        XCTAssertNil(builder().attribution(for: Values.review(usedOn: nil)).usedOnText)
    }

    /// 責務: 利用日を、日本時間の日付(UTC では前日の 2026-11-20 16:00)で利用日の書式に入れることを確かめます。
    func testUsedOnUsesNumericDateInTimeZone() {
        let text = builder().attribution(for: Values.review(usedOn: usedOn)).usedOnText

        XCTAssertEqual(text, "U:2026/11/21")
    }

    /// 責務: 注入したタイムゾーン(UTC)で日付を決めることを確かめます。
    func testUsedOnFollowsInjectedTimeZone() {
        guard let utc = TimeZone(identifier: "UTC") else {
            return XCTFail("UTC を作れません")
        }

        let text = builder(timeZone: utc).attribution(for: Values.review(usedOn: usedOn)).usedOnText

        XCTAssertEqual(text, "U:2026/11/20")
    }

    /// 責務: 和暦を既定にするロケールでも、西暦の年で日付を出すことを確かめます。
    func testUsedOnUsesGregorianYear() {
        let text = builder(locale: "ja_JP@calendar=japanese").attribution(for: Values.review(usedOn: usedOn)).usedOnText

        XCTAssertEqual(text, "U:2026/11/21")
    }

    /// 責務: 配布ページの URL をそのまま受け渡すことを確かめます。
    func testPassesSourceURL() {
        XCTAssertEqual(builder().attribution(for: Values.review()).sourceURL, Values.sourceURL)
    }

    /// 責務: `empty` が、版の行は空・利用日と URL は nil であることを確かめます。
    func testEmptyAttribution() {
        let empty = SessionRoadRegulationReviewAttribution.empty

        XCTAssertEqual(empty.datasetTexts, [])
        XCTAssertNil(empty.usedOnText)
        XCTAssertNil(empty.sourceURL)
    }
}
