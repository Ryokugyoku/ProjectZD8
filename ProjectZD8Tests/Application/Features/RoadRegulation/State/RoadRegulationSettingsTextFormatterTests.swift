import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationSettingsTextFormatter` が、書式への値の差し込み・百分率・年月・日付をロケールとタイムゾーンに合わせて作ることを検証します。
@MainActor
final class RoadRegulationSettingsTextFormatterTests: XCTestCase {
    private static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
    /// 2026-08-31 20:00 UTC。UTC では 8月31日、Asia/Tokyo では 9月1日 05:00。
    private static let utcAugustTokyoSeptember = Date(timeIntervalSince1970: 1_788_206_400)

    /// 注入する書式(キー → 固定の書式)です。
    private static let formats: [String: String] = [
        "road_regulation.settings.summary.none": "NONE",
        "road_regulation.settings.summary.count": "C=%lld M=%@",
        "road_regulation.detail.data_month": "DM=%@",
        "road_regulation.detail.downloaded_at": "DL=%@",
        "road_regulation.detail.count": "N=%lld",
        "road_regulation.detail.rejected": "R=%lld",
        "road_regulation.attribution.used_on": "U=%@",
    ]

    /// 責務: 固定の書式・ロケール・日本のタイムゾーンで整形器を作ります。
    private func formatter(_ identifier: String = "en_US") -> RoadRegulationSettingsTextFormatter {
        RoadRegulationSettingsTextFormatter(
            localizedFormat: { Self.formats[$0] ?? "MISSING(\($0))" }, locale: Locale(identifier: identifier), timeZone: Self.tokyo
        )
    }

    /// 責務: まとめを作ります。
    private func summary(count: Int, month: RoadRegulationDataMonth?) -> RoadRegulationSettingsSummary {
        RoadRegulationSettingsSummary(downloadedCount: count, oldestDataMonth: month, latestDownloadedAt: nil, isImporting: false)
    }

    /// 責務: 版を作ります(基準月・取得日時・件数を指定)。
    private func dataset(month: RoadRegulationDataMonth, downloadedAt: Date, imported: Int, rejected: [RoadRegulationRowRejection: Int])
        -> RoadRegulationDataset {
        let base = RoadRegulationTestValues.dataset(RoadRegulationTestValues.prefecture(13), month: month, downloadedAt: downloadedAt)
        return RoadRegulationDataset(
            id: base.id, prefecture: base.prefecture, state: base.state, dataMonth: base.dataMonth,
            publicationStamp: base.publicationStamp, sourceURL: base.sourceURL, downloadedAt: base.downloadedAt,
            activatedAt: base.activatedAt, formatVersion: base.formatVersion,
            counts: RoadRegulationTestValues.counts(totalRows: 100, imported: imported, rejected: rejected), coverage: base.coverage
        )
    }

    /// 取得済みが0件なら、基準月があっても「ありません」の文言です。
    ///
    /// 責務: `summaryText` の件数0の分岐を確認します。
    func testSummaryWithZeroCountIsNone() {
        XCTAssertEqual(formatter().summaryText(summary(count: 0, month: RoadRegulationTestValues.month(2026, 9))), "NONE")
        XCTAssertEqual(formatter().summaryText(summary(count: 0, month: nil)), "NONE")
    }

    /// 基準月が nil なら、件数があっても「ありません」の文言です。
    ///
    /// 責務: `summaryText` の基準月 nil の分岐を確認します。
    func testSummaryWithoutMonthIsNone() {
        XCTAssertEqual(formatter().summaryText(summary(count: 3, month: nil)), "NONE")
    }

    /// 件数と基準月があれば、書式に件数と年月を差し込みます(ロケールごと)。
    ///
    /// 責務: `summaryText` の通常の分岐を確認します。
    func testSummaryWithCountAndMonth() {
        let value = summary(count: 3, month: RoadRegulationTestValues.month(2026, 9))

        XCTAssertEqual(formatter("en_US").summaryText(value), "C=3 M=September 2026")
        XCTAssertEqual(formatter("ja_JP").summaryText(value), "C=3 M=2026年9月")
        XCTAssertEqual(formatter().summaryText(summary(count: 1, month: RoadRegulationTestValues.month(2026, 9))), "C=1 M=September 2026")
    }

    /// 基準月の行・取得日の行・件数の行・捨てた件数の行が、それぞれの書式に値を差し込みます。
    ///
    /// 責務: 版の4つの行の文言を確認します。捨てた件数は理由ごとの合計です。
    func testDatasetLines() {
        let value = dataset(
            month: RoadRegulationTestValues.month(2026, 9), downloadedAt: Self.utcAugustTokyoSeptember, imported: 56,
            rejected: [.invalidSpeed: 3, .shapeMismatch: 4]
        )
        let en = formatter("en_US")

        XCTAssertEqual(en.dataMonthLine(value), "DM=September 2026")
        XCTAssertEqual(en.downloadedAtLine(value), "DL=Sep 1, 2026")
        XCTAssertEqual(en.regulationCountLine(value), "N=56")
        XCTAssertEqual(en.rejectedCountLine(value), "R=7")
        XCTAssertEqual(formatter("ja_JP").dataMonthLine(value), "DM=2026年9月")
    }

    /// 捨てた行が無ければ 0 件です。
    ///
    /// 責務: `rejectedCountLine` の境界(空)を確認します。
    func testRejectedCountLineWithNoRejections() {
        let value = dataset(month: RoadRegulationTestValues.month(2026, 9), downloadedAt: Self.utcAugustTokyoSeptember, imported: 0, rejected: [:])

        XCTAssertEqual(formatter().rejectedCountLine(value), "R=0")
        XCTAssertEqual(formatter().regulationCountLine(value), "N=0")
    }

    /// 利用日が無ければ nil、あれば書式に日付を差し込みます。
    ///
    /// 責務: `usedOnText` の2分岐を確認します。
    func testUsedOnText() {
        XCTAssertNil(formatter().usedOnText(RoadRegulationAttribution(datasets: [])))
        let value = dataset(month: RoadRegulationTestValues.month(2026, 9), downloadedAt: Self.utcAugustTokyoSeptember, imported: 1, rejected: [:])

        XCTAssertEqual(formatter().usedOnText(RoadRegulationAttribution(datasets: [value])), "U=Sep 1, 2026")
    }

    /// 進み具合は 0...1 に切り詰めた小数なしの百分率です。
    ///
    /// 責務: `progressPercentText` の通常値と境界(内側・外側)を確認します。
    func testProgressPercentText() {
        let text = formatter()

        XCTAssertEqual(text.progressPercentText(0.5), "50%")
        XCTAssertEqual(text.progressPercentText(0), "0%")
        XCTAssertEqual(text.progressPercentText(1), "100%")
        XCTAssertEqual(text.progressPercentText(0.994), "99%")
        XCTAssertEqual(text.progressPercentText(0.996), "100%")
        XCTAssertEqual(text.progressPercentText(-0.001), "0%")
        XCTAssertEqual(text.progressPercentText(-5), "0%")
        XCTAssertEqual(text.progressPercentText(1.001), "100%")
        XCTAssertEqual(text.progressPercentText(250), "100%")
        XCTAssertEqual(formatter("ja_JP").progressPercentText(0.5), "50%")
    }

    /// 有限でない値は 0 とみなします(NaN・正と負の無限大)。
    ///
    /// 責務: `progressPercentText` の非有限の分岐を確認します。
    func testProgressPercentTextNonFinite() {
        XCTAssertEqual(formatter().progressPercentText(.nan), "0%")
        XCTAssertEqual(formatter().progressPercentText(.infinity), "0%")
        XCTAssertEqual(formatter().progressPercentText(-.infinity), "0%")
    }

    /// 基準月は西暦の年と月(wide)で、ロケールに合わせます。
    ///
    /// 責務: `dataMonthText` を英語・日本語、年の端と月の端で確認します。
    func testDataMonthText() {
        XCTAssertEqual(formatter("en_US").dataMonthText(RoadRegulationTestValues.month(2026, 9)), "September 2026")
        XCTAssertEqual(formatter("ja_JP").dataMonthText(RoadRegulationTestValues.month(2026, 9)), "2026年9月")
        XCTAssertEqual(formatter("en_US").dataMonthText(RoadRegulationTestValues.month(2026, 1)), "January 2026")
        XCTAssertEqual(formatter("en_US").dataMonthText(RoadRegulationTestValues.month(2026, 12)), "December 2026")
        XCTAssertEqual(formatter("ja_JP").dataMonthText(RoadRegulationTestValues.month(2000, 1)), "2000年1月")
        XCTAssertEqual(formatter("ja_JP").dataMonthText(RoadRegulationTestValues.month(2999, 12)), "2999年12月")
    }

    /// 日付は年月日だけで時刻を含まず、注入したタイムゾーンの日付になります。
    ///
    /// 責務: `dateText` を、UTC では前日になる時刻で確認します。
    func testDateTextUsesInjectedTimeZoneAndOmitsTime() {
        let en = formatter("en_US").dateText(Self.utcAugustTokyoSeptember)
        let ja = formatter("ja_JP").dateText(Self.utcAugustTokyoSeptember)

        XCTAssertEqual(en, "Sep 1, 2026")
        XCTAssertTrue(ja.contains("2026"), ja)
        XCTAssertTrue(ja.contains("9月1日"), ja)
        XCTAssertFalse(en.contains(":"))
        XCTAssertFalse(ja.contains(":"))
        XCTAssertFalse(en.contains("Aug"))
    }

    /// 同じ時刻でもタイムゾーンを変えると日付が変わります(注入したタイムゾーンが使われている)。
    ///
    /// 責務: `timeZone` の注入が効くことを確認します。
    func testDateTextFollowsTimeZone() {
        let utc = RoadRegulationSettingsTextFormatter(
            localizedFormat: { $0 }, locale: Locale(identifier: "en_US"), timeZone: .gmt
        )

        XCTAssertEqual(utc.dateText(Self.utcAugustTokyoSeptember), "Aug 31, 2026")
        XCTAssertEqual(formatter("en_US").dateText(Self.utcAugustTokyoSeptember), "Sep 1, 2026")
    }

    /// 書式のキーの定数は、設計の綴りと一致します。
    ///
    /// 責務: 公開している書式キーを確認します。
    func testFormatKeys() {
        XCTAssertEqual(RoadRegulationSettingsTextFormatter.dataMonthKey, "road_regulation.detail.data_month")
        XCTAssertEqual(RoadRegulationSettingsTextFormatter.downloadedAtKey, "road_regulation.detail.downloaded_at")
        XCTAssertEqual(RoadRegulationSettingsTextFormatter.regulationCountKey, "road_regulation.detail.count")
        XCTAssertEqual(RoadRegulationSettingsTextFormatter.rejectedCountKey, "road_regulation.detail.rejected")
    }
}
