import Foundation
import XCTest
@testable import ProjectZD8

/// 照合結果から一度だけ作る内容が、部品の結果を組み合わせるだけであることを検証します(設計書 §3.3 ContentBuilder、§7 TC1b)。
@MainActor
final class SessionRoadRegulationReviewContentBuilderTests: XCTestCase {
    /// 値の短い名前です。
    private typealias Values = SessionRoadRegulationReviewTestValues

    /// 行の部品(時刻と書式を固定)です。
    private let rowBuilder = SessionRoadRegulationReviewRowBuilder(
        formatter: SessionRoadRegulationReviewRowFormatter(
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: SessionRoadRegulationReviewTestValues.tokyo,
            localize: SessionRoadRegulationReviewTestValues.bracketLocalize
        )
    )
    /// 出典の部品(日付と書式を固定)です。
    private let attributionBuilder = SessionRoadRegulationReviewAttributionBuilder(
        locale: Locale(identifier: "ja_JP"),
        timeZone: SessionRoadRegulationReviewTestValues.tokyo,
        localize: SessionRoadRegulationReviewTestValues.bracketLocalize
    )

    /// 固定した部品を渡した検証対象を作ります。
    ///
    /// 責務: 言語設定に依存しない部品で組み立てた builder を返します。
    /// - Returns: builder。
    private func builder() -> SessionRoadRegulationReviewContentBuilder {
        SessionRoadRegulationReviewContentBuilder(
            rowBuilder: rowBuilder,
            summaryBuilder: SessionRoadRegulationReviewSummaryBuilder(),
            noticeBuilder: SessionRoadRegulationReviewNoticeBuilder(),
            attributionBuilder: attributionBuilder
        )
    }

    /// 車速なし・指定なしの行を含む照合結果です。
    ///
    /// 責務: 一時停止(0秒)と最高速度の指定なし(10秒)を、入力では逆の順に持つ結果を返します。
    /// - Returns: 照合結果。
    private func review() -> SessionRoadRegulationReview {
        let unregulated = Values.entry(
            kind: .speedLimit, outcome: .unregulated, verdictKey: "unregulated",
            start: Values.mark(10, sequence: 10), end: Values.mark(20, sequence: 20)
        )
        let notStopped = Values.entry(
            kind: .stop, outcome: .possibleIssue, verdictKey: "notStopped",
            start: Values.mark(0, sequence: 0), end: Values.mark(5, sequence: 5)
        )
        return Values.review(entries: [unregulated, notStopped], hasVehicleSpeed: false, usedOn: Values.base)
    }

    /// 責務: rows が行の部品の結果そのもので、開始の時刻の順(一時停止 → 最高速度)に並ぶことを確かめます。
    func testRowsComeFromRowBuilder() {
        let content = builder().content(for: review(), rawLog: .onDevice)

        XCTAssertEqual(content.rows, rowBuilder.rows(from: review().entries))
        XCTAssertEqual(content.rows.map(\.titleKey), ["notStopped", "unregulated"])
    }

    /// 責務: summaries が rows から数えた結果で、4種類のうち最高速度と一時停止だけが1件であることを確かめます。
    func testSummariesComeFromRows() {
        let content = builder().content(for: review(), rawLog: .onDevice)

        XCTAssertEqual(content.summaries, SessionRoadRegulationReviewSummaryBuilder().summaries(for: content.rows))
        XCTAssertEqual(content.summaries.map(\.total), [1, 1, 0, 0])
    }

    /// 責務: notices が rawLog と rows を使い、端末にある時は「車速の記録なし」と「指定なし」の2件であることを確かめます。
    func testNoticesUseRawLogAndRows() {
        let content = builder().content(for: review(), rawLog: .onDevice)

        XCTAssertEqual(content.notices, [.speedNotRecorded, .unregulatedExplained])
    }

    /// 責務: attribution が出典の部品の結果そのもの(版1つ・利用日・URL)であることを確かめます。
    func testAttributionComesFromAttributionBuilder() {
        let content = builder().content(for: review(), rawLog: .onDevice)

        XCTAssertEqual(content.attribution, attributionBuilder.attribution(for: review()))
        XCTAssertEqual(content.attribution.datasetTexts.count, 1)
        XCTAssertNotNil(content.attribution.usedOnText)
        XCTAssertEqual(content.attribution.sourceURL, Values.sourceURL)
    }

    /// 責務: `.inCloud` と `.onDevice` では notices だけが変わり、rows・summaries・attribution は同じであることを確かめます。
    func testOnlyNoticesDependOnRawLog() {
        let cloud = builder().content(for: review(), rawLog: .inCloud)
        let device = builder().content(for: review(), rawLog: .onDevice)

        XCTAssertEqual(cloud.notices, [.speedInCloud, .unregulatedExplained])
        XCTAssertNotEqual(cloud.notices, device.notices)
        XCTAssertEqual(cloud.rows, device.rows)
        XCTAssertEqual(cloud.summaries, device.summaries)
        XCTAssertEqual(cloud.attribution, device.attribution)
    }
}
