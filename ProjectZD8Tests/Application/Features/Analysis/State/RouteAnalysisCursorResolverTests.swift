import Foundation
import XCTest
@testable import ProjectZD8

/// グラフで選んだ時刻から地図の印と読み出しを求める規則(位置 5 s 以内、値 2 s 以内)を検証します(設計書 §2.3)。
///
/// 地図 → グラフの向き(`date(nearestTo:in:)`)は `RouteAnalysisCursorResolverReverseTests` で確かめます。
@MainActor
final class RouteAnalysisCursorResolverTests: XCTestCase {
    private typealias Fixtures = RouteAnalysisRouteTimelineFixtures

    /// 数値の文字に使う、ロケールを固定した整形です。
    private let formatter = SessionLogAnalysisTextFormatter(locale: Locale(identifier: "en_US"))
    /// 検証対象です。
    private lazy var resolver = RouteAnalysisCursorResolver(formatter: formatter)
    /// 0 s・10 s・20 s の3点(10 s の点だけ標高 123 m)の時間の軸です。
    private let timeline = Fixtures.timeline(points: [
        Fixtures.point(index: 0, sequence: 0, segmentIndex: 0, x: 0, seconds: 0),
        Fixtures.point(index: 1, sequence: 1, segmentIndex: 0, x: 100, seconds: 10, altitude: 123),
        Fixtures.point(index: 2, sequence: 2, segmentIndex: 0, x: 200, seconds: 20)
    ])

    /// 文字列の数字だけを取り出します。
    ///
    /// 責務: 桁区切りや単位に左右されずに数値を比べられるようにします。
    /// - Parameter text: 文字列。
    /// - Returns: 数字だけの文字列。
    private func digits(_ text: String?) -> String? {
        text.map { String($0.filter(\.isNumber)) }
    }

    /// 責務: 最も近い位置まで 5 s の少し内側(4.9 s)なら、その位置の座標が付き、選んだ時刻が残ることを確かめます。
    func testWithinToleranceGivesCoordinate() {
        let cursor = resolver.cursor(at: Fixtures.date(14.9), timeline: timeline, values: nil, unit: nil)

        XCTAssertEqual(cursor.date, Fixtures.date(14.9))
        XCTAssertEqual(cursor.coordinate, timeline.points[1].coordinate)
    }

    /// 責務: 最も近い位置まで 5 s の少し外側(5.1 s)なら座標と標高の文字は無く、選んだ時刻から 2 s 以内の値の文字は出ることを確かめます。
    func testBeyondPointToleranceKeepsNearbyValue() {
        let values = RouteAnalysisValueSeriesFixtures.series([(26, 40)])

        let cursor = resolver.cursor(at: Fixtures.date(25.1), timeline: timeline, values: values, unit: "km/h")

        XCTAssertEqual(cursor.date, Fixtures.date(25.1))
        XCTAssertNil(cursor.coordinate)
        XCTAssertNil(cursor.elevationText)
        XCTAssertEqual(cursor.metricValueText, formatter.measurementText(40, unit: "km/h"))
    }

    /// 責務: 最も近い位置まで 5.1 s 離れ、選んだ時刻から 2 s 以内に値も無ければ、時刻だけの読み出しになることを確かめます。
    func testBeyondPointToleranceWithoutNearbyValueGivesOnlyDate() {
        let values = RouteAnalysisValueSeriesFixtures.series([(28, 40)])

        let cursor = resolver.cursor(at: Fixtures.date(25.1), timeline: timeline, values: values, unit: "km/h")

        XCTAssertEqual(cursor, RouteAnalysisCursor(date: Fixtures.date(25.1), coordinate: nil, metricValueText: nil, elevationText: nil))
    }

    /// 責務: 点の無い時間の軸では、時刻だけの読み出しになることを確かめます。
    func testEmptyTimelineGivesOnlyDate() {
        let cursor = resolver.cursor(at: Fixtures.date(3), timeline: Fixtures.timeline(points: []), values: nil, unit: nil)

        XCTAssertEqual(cursor, RouteAnalysisCursor(date: Fixtures.date(3), coordinate: nil, metricValueText: nil, elevationText: nil))
    }

    /// 責務: 選んだ時刻から 2 s 以内(1.9 s)の値は、整形した数値と単位の文字になることを確かめます。
    func testMetricValueWithinTwoSeconds() {
        let values = RouteAnalysisValueSeriesFixtures.series([(11.9, 42.5)])

        let cursor = resolver.cursor(at: Fixtures.date(10), timeline: timeline, values: values, unit: "km/h")

        XCTAssertEqual(cursor.metricValueText, formatter.measurementText(42.5, unit: "km/h"))
    }

    /// 責務: 選んだ時刻から 2 s を超える(2.5 s)値しか無ければ、値の文字が無いことを確かめます。
    func testMetricValueBeyondTwoSecondsIsNil() {
        let values = RouteAnalysisValueSeriesFixtures.series([(12.5, 42.5)])

        let cursor = resolver.cursor(at: Fixtures.date(10), timeline: timeline, values: values, unit: "km/h")

        XCTAssertNil(cursor.metricValueText)
        XCTAssertEqual(cursor.coordinate, timeline.points[1].coordinate)
    }

    /// 責務: 値の列を渡さなければ、値の文字が無いことを確かめます。
    func testNoValuesGiveNoMetricText() {
        let cursor = resolver.cursor(at: Fixtures.date(10), timeline: timeline, values: nil, unit: "km/h")

        XCTAssertNil(cursor.metricValueText)
    }

    /// 責務: 印の位置に標高があれば、その数値の標高の文字が付くことを確かめます。
    func testElevationTextFromNearestPoint() {
        let cursor = resolver.cursor(at: Fixtures.date(10), timeline: timeline, values: nil, unit: nil)

        XCTAssertEqual(digits(cursor.elevationText), "123")
    }

    /// 責務: 印の位置に標高が無ければ、標高の文字が無いことを確かめます。
    func testNoElevationTextWithoutAltitude() {
        let cursor = resolver.cursor(at: Fixtures.date(0), timeline: timeline, values: nil, unit: nil)

        XCTAssertEqual(cursor.coordinate, timeline.points[0].coordinate)
        XCTAssertNil(cursor.elevationText)
    }

    /// 責務: 初期化で渡した位置の許容差(1 s)が、内側(0.9 s)と外側(1.1 s)の判定に使われることを確かめます。
    func testCustomPointToleranceIsApplied() {
        let strict = RouteAnalysisCursorResolver(pointToleranceSeconds: 1, formatter: formatter)

        XCTAssertEqual(strict.cursor(at: Fixtures.date(10.9), timeline: timeline, values: nil, unit: nil).coordinate, timeline.points[1].coordinate)
        XCTAssertNil(strict.cursor(at: Fixtures.date(11.1), timeline: timeline, values: nil, unit: nil).coordinate)
    }

    /// 責務: 単位を渡さなければ値の列の単位を使い、どちらも無ければ数値だけの文字になることを確かめます。
    func testMetricUnitFallsBackToSeriesUnit() {
        let withSeriesUnit = RouteAnalysisValueSeriesFixtures.series([(10, 42.5)], unit: "mph")
        let withoutUnit = RouteAnalysisValueSeriesFixtures.series([(10, 42.5)], unit: nil)

        let fromSeries = resolver.cursor(at: Fixtures.date(10), timeline: timeline, values: withSeriesUnit, unit: nil)
        let numberOnly = resolver.cursor(at: Fixtures.date(10), timeline: timeline, values: withoutUnit, unit: nil)

        XCTAssertEqual(fromSeries.metricValueText, formatter.measurementText(42.5, unit: "mph"))
        XCTAssertEqual(digits(numberOnly.metricValueText), "425")
        XCTAssertEqual(numberOnly.metricValueText?.contains(where: \.isLetter), false)
    }
}
