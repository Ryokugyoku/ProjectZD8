import Foundation
import XCTest
@testable import ProjectZD8

/// 照合結果の entry から一覧の行を作る規則を検証します(設計書 §3.2 Row、§3.3 RowBuilder、§7 TC1a)。
///
/// 並べ方は「開始の observedAt の昇順 → 種類の順 → 入力の順」、id は並べた後の位置です。
@MainActor
final class SessionRoadRegulationReviewRowBuilderTests: XCTestCase {
    /// 値の短い名前です。
    private typealias Values = SessionRoadRegulationReviewTestValues

    /// 時刻を日本時間・en_US_POSIX、数値の書式を `キー=%@` に固定した検証対象です。
    private let builder = SessionRoadRegulationReviewRowBuilder(
        formatter: SessionRoadRegulationReviewRowFormatter(
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: SessionRoadRegulationReviewTestValues.tokyo,
            localize: { "\($0)=%@" }
        ),
        keys: SessionRoadRegulationReviewTextKeys()
    )

    /// 開始と終了の秒・連番を指定した entry を作ります。
    ///
    /// 責務: 並びの検証用に、文言キーで見分けられる entry を返します。
    /// - Parameters:
    ///   - kind: 種類。
    ///   - start: 開始の秒(連番も同じ値)。
    ///   - key: 判定の文言キー。
    ///   - outcome: 結果。
    /// - Returns: entry。
    private func entry(
        _ kind: SessionRoadRegulationReviewKind,
        start: TimeInterval,
        key: String,
        outcome: SessionRoadRegulationReviewOutcome = .compliant
    ) -> SessionRoadRegulationReviewEntry {
        Values.entry(
            kind: kind,
            outcome: outcome,
            verdictKey: key,
            start: Values.mark(start, sequence: Int64(start)),
            end: Values.mark(start + 5, sequence: Int64(start) + 5)
        )
    }

    /// 責務: entry が無ければ空の配列を返すことを確かめます。
    func testEmptyEntriesGiveNoRows() {
        XCTAssertEqual(builder.rows(from: []), [])
    }

    /// 責務: 開始の時刻の昇順に並べ、時刻が先なら種類の順より優先し、id を 0 からの連番にすることを確かめます。
    func testSortsByStartTimeBeforeKind() {
        let entries = [
            entry(.speedLimit, start: 30, key: "c"),
            entry(.slowDown, start: 10, key: "a"),
            entry(.stop, start: 20, key: "b")
        ]

        let rows = builder.rows(from: entries)

        XCTAssertEqual(rows.map(\.titleKey), ["a", "b", "c"])
        XCTAssertEqual(rows.map(\.id), [0, 1, 2])
    }

    /// 責務: 開始の時刻が同じなら、種類の順(最高速度 → 一時停止 → 一方通行 → 徐行)に並べることを確かめます。
    func testSameStartTimeSortsByKind() {
        let entries = [
            entry(.slowDown, start: 10, key: "slowDown"),
            entry(.oneWay, start: 10, key: "oneWay"),
            entry(.stop, start: 10, key: "stop"),
            entry(.speedLimit, start: 10, key: "speedLimit")
        ]

        let rows = builder.rows(from: entries)

        XCTAssertEqual(rows.map(\.kind), [.speedLimit, .stop, .oneWay, .slowDown])
        XCTAssertEqual(rows.map(\.id), [0, 1, 2, 3])
    }

    /// 責務: 開始の時刻も種類も同じなら、入力の順を保つ(安定な並べ替え)ことを確かめます。
    func testSameStartAndKindKeepsInputOrder() {
        let entries = [
            entry(.stop, start: 10, key: "first"),
            entry(.stop, start: 10, key: "second"),
            entry(.stop, start: 10, key: "third"),
            entry(.stop, start: 5, key: "earliest")
        ]

        XCTAssertEqual(builder.rows(from: entries).map(\.titleKey), ["earliest", "first", "second", "third"])
    }

    /// 責務: 終了が開始より前でも、時刻と連番の範囲を min…max にすることを確かめます。
    func testReversedEndpointsGiveMinMaxRanges() {
        let reversed = Values.entry(
            kind: .oneWay,
            outcome: .possibleIssue,
            start: Values.mark(20, sequence: 50),
            end: Values.mark(5, sequence: 10)
        )

        let rows = builder.rows(from: [reversed])

        XCTAssertEqual(rows.first?.timeRange, Values.date(5)...Values.date(20))
        XCTAssertEqual(rows.first?.sequenceRange, 10...50)
    }

    /// 責務: 順向きの区間では、時刻と連番の範囲を開始…終了のまま余白なしで持つことを確かめます。
    func testForwardEndpointsKeepRanges() {
        let forward = Values.entry(kind: .stop, outcome: .compliant, start: Values.mark(3, sequence: 7), end: Values.mark(9, sequence: 21))

        let rows = builder.rows(from: [forward])

        XCTAssertEqual(rows.first?.timeRange, Values.date(3)...Values.date(9))
        XCTAssertEqual(rows.first?.sequenceRange, 7...21)
    }

    /// 責務: 種類・結果・文言キー(= verdictKey)・重ね合わせの ID・色・記号が entry と表引きの表どおりであることを確かめます。
    func testCopiesKeysAndLooksUpPresentation() throws {
        let issue = Values.entry(
            kind: .speedLimit, outcome: .possibleIssue, verdictKey: "verdict.exceeded",
            start: Values.mark(0, sequence: 0), end: Values.mark(1, sequence: 1)
        )
        let observed = Values.entry(
            kind: .slowDown, outcome: .observedOnly, verdictKey: "verdict.observed",
            start: Values.mark(2, sequence: 2), end: Values.mark(3, sequence: 3)
        )

        let rows = builder.rows(from: [issue, observed])
        let first = try XCTUnwrap(rows.first)
        let second = try XCTUnwrap(rows.last)

        XCTAssertEqual(first.kind, .speedLimit)
        XCTAssertEqual(first.outcome, .possibleIssue)
        XCTAssertEqual(first.titleKey, "verdict.exceeded")
        XCTAssertEqual(first.overlayID, "road_regulation.speed_limit")
        XCTAssertEqual(first.category, .tone(.caution))
        XCTAssertEqual(first.systemImage, "exclamationmark.triangle.fill")
        XCTAssertEqual(second.titleKey, "verdict.observed")
        XCTAssertEqual(second.overlayID, "road_regulation.slow_down")
        XCTAssertEqual(second.category, .tone(.neutral))
        XCTAssertEqual(second.systemImage, "gauge.with.dots.needle.33percent")
    }

    /// 責務: 判定できない理由を受け渡し、理由の無い entry は nil のままであることを確かめます。
    func testPassesUndeterminedReason() {
        let undetermined = Values.entry(
            kind: .oneWay,
            outcome: .undeterminable,
            reason: .headingUnknown,
            start: Values.mark(0, sequence: 0),
            end: Values.mark(1, sequence: 1)
        )
        let compliant = Values.entry(kind: .oneWay, outcome: .compliant, start: Values.mark(2, sequence: 2), end: Values.mark(3, sequence: 3))

        let rows = builder.rows(from: [undetermined, compliant])

        XCTAssertEqual(rows.map(\.undeterminedReason), [.headingUnknown, nil])
        XCTAssertEqual(rows.first?.category, .tone(.unknown))
        XCTAssertEqual(rows.first?.systemImage, "questionmark.circle")
    }

    /// 責務: 時刻と数値の文字列を注入した formatter の規則で作る(17:00:00–17:00:35、制限と最高)ことを確かめます。
    func testFormatsTimeAndFigures() {
        let figures = SessionRoadRegulationReviewFigures(limitKph: 40, maximumKph: 52.26)
        let speed = Values.entry(
            kind: .speedLimit, outcome: .compliant,
            start: Values.mark(0, sequence: 0), end: Values.mark(35, sequence: 9), figures: figures
        )

        let rows = builder.rows(from: [speed])

        XCTAssertEqual(rows.first?.timeText, "17:00:00\u{2013}17:00:35")
        XCTAssertEqual(rows.first?.figureTexts, ["analysis.road_regulation.figure.limit=40 km/h", "analysis.road_regulation.figure.maximum=52.3 km/h"])
    }
}
