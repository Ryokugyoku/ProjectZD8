import Foundation
import XCTest
@testable import ProjectZD8

/// 指標のグラフ用の点列を作る規則(点数の上限 600、線の切れ目 10 s、単位、最小と最大)を検証します(設計書 §2.3、§6)。
///
/// 標高のグラフは `RouteAnalysisChartSeriesBuilderElevationTests` で確かめます。
@MainActor
final class RouteAnalysisChartSeriesBuilderTests: XCTestCase {
    private typealias Values = RouteAnalysisValueSeriesFixtures

    /// 既定(600 点、10 s)の検証対象です。
    private let builder = RouteAnalysisChartSeriesBuilder()

    /// 1秒おきの値から列を作ります。
    ///
    /// 責務: 値の列を、基準から 0, 1, 2… 秒の標本の列にします。
    /// - Parameters:
    ///   - values: 値。
    ///   - unit: 単位。
    /// - Returns: 値の列。
    private func everySecond(_ values: [Double], unit: String? = "km/h") -> RouteAnalysisValueSeries {
        Values.series(values.enumerated().map { (seconds: TimeInterval($0.offset), value: $0.element) }, unit: unit)
    }

    /// 責務: 空の列からはグラフができないことを確かめます。
    func testEmptySeriesGivesNil() {
        XCTAssertNil(builder.metricSeries(everySecond([]), metric: .vehicleSpeed))
    }

    /// 責務: 600 点以下の列は、日時と値をそのままの順で持ち、点の ID が重ならないことを確かめます。
    func testSmallSeriesKeepsAllPoints() throws {
        let series = everySecond([5, 7, 3, 9, 1])

        let chart = try XCTUnwrap(builder.metricSeries(series, metric: .vehicleSpeed))

        XCTAssertEqual(chart.points.map(\.date), series.samples.map(\.date))
        XCTAssertEqual(chart.points.map(\.value), [5, 7, 3, 9, 1])
        XCTAssertEqual(chart.points.map(\.id), [0, 1, 2, 3, 4])
        XCTAssertEqual(chart.titleKey, RouteAnalysisColorMetric.vehicleSpeed.titleKey)
    }

    /// 責務: 1点だけの列からもグラフができることを確かめます。
    func testSingleSampleGivesSeries() throws {
        let chart = try XCTUnwrap(builder.metricSeries(everySecond([42]), metric: .engineLoad))

        XCTAssertEqual(chart.points.map(\.value), [42])
        XCTAssertEqual(chart.minimum, 42)
        XCTAssertEqual(chart.maximum, 42)
    }

    /// 責務: 間引いた後の点の ID が、間引いた後の位置(0 からの連番)になることを確かめます。
    func testReducedPointIDsArePositions() throws {
        let chart = try XCTUnwrap(builder.metricSeries(everySecond((0..<1_000).map { Double($0 % 23) }), metric: .vehicleSpeed))

        XCTAssertEqual(chart.points.map(\.id), Array(0..<chart.points.count))
        XCTAssertEqual(chart.points.map(\.date), chart.points.map(\.date).sorted())
    }

    /// 責務: 点数の上限が 2 未満なら、先頭から上限の数の点だけになることを確かめます。
    func testMaximumBelowTwoKeepsLeadingPoints() throws {
        let tiny = RouteAnalysisChartSeriesBuilder(maximumPointCount: 1)

        let chart = try XCTUnwrap(tiny.metricSeries(everySecond([5, 9, 1]), metric: .vehicleSpeed))

        XCTAssertEqual(chart.points.map(\.value), [5])
        XCTAssertEqual(chart.minimum, 1)
        XCTAssertEqual(chart.maximum, 9)
    }

    /// 責務: 最小と最大が、列の値の最小と最大になることを確かめます。
    func testMinimumAndMaximum() throws {
        let chart = try XCTUnwrap(builder.metricSeries(everySecond([5, -2, 30, 4]), metric: .engineLoad))

        XCTAssertEqual(chart.minimum, -2)
        XCTAssertEqual(chart.maximum, 30)
    }

    /// 責務: 単位は列の単位を優先し、無ければ指標の既定の単位になることを確かめます。
    func testUnitPrefersSeriesUnit() throws {
        let withUnit = try XCTUnwrap(builder.metricSeries(everySecond([1, 2], unit: "mph"), metric: .vehicleSpeed))
        let withoutUnit = try XCTUnwrap(builder.metricSeries(everySecond([1, 2], unit: nil), metric: .coolantTemperature))

        XCTAssertEqual(withUnit.unit, "mph")
        XCTAssertEqual(withoutUnit.unit, "°C")
    }

    /// 責務: 時間差が 9 s なら同じ線のまま、11 s なら次の線(lineID が 0 から1つ進む)になることを確かめます。
    func testLineBreaksOnlyBeyondTenSeconds() throws {
        let series = Values.series([(0, 1), (9, 2), (20, 3), (21, 4)])

        let chart = try XCTUnwrap(builder.metricSeries(series, metric: .vehicleSpeed))

        let lineIDs = chart.points.map(\.lineID)
        XCTAssertEqual(lineIDs, [0, 0, 1, 1])
    }

    /// 責務: ちょうど 600 点の列は減らさないことを確かめます。
    func testExactlyMaximumPointCountIsKept() throws {
        let values: [Double] = (0..<600).map { Double($0 % 37) }

        let chart = try XCTUnwrap(builder.metricSeries(everySecond(values), metric: .vehicleSpeed))

        XCTAssertEqual(chart.points.count, 600)
    }

    /// 責務: 600 点を超える列は 600 点以下に減り、全体の最小と最大の点(日時と値)を含むことを確かめます。
    func testLargeSeriesIsReducedAndKeepsExtremes() throws {
        var values: [Double] = (0..<2_000).map { 50 + 20 * sin(Double($0) / 15) }
        values[1_234] = -40
        values[321] = 180
        let series = everySecond(values)

        let chart = try XCTUnwrap(builder.metricSeries(series, metric: .vehicleSpeed))

        XCTAssertLessThanOrEqual(chart.points.count, 600)
        XCTAssertTrue(chart.points.contains { $0.date == series.samples[1_234].date && $0.value == -40 })
        XCTAssertTrue(chart.points.contains { $0.date == series.samples[321].date && $0.value == 180 })
        XCTAssertEqual(chart.minimum, -40)
        XCTAssertEqual(chart.maximum, 180)
    }

    /// 責務: 初期化で渡した点数の上限と線の切れ目の秒が使われることを確かめます。
    func testCustomLimitsAreApplied() throws {
        let custom = RouteAnalysisChartSeriesBuilder(maximumPointCount: 10, lineBreakSeconds: 2)
        let reduced = try XCTUnwrap(custom.metricSeries(everySecond((0..<50).map(Double.init)), metric: .vehicleSpeed))
        let gapped = try XCTUnwrap(custom.metricSeries(Values.series([(0, 1), (2, 2), (4.5, 3)]), metric: .vehicleSpeed))

        XCTAssertLessThanOrEqual(reduced.points.count, 10)
        let lineIDs = gapped.points.map(\.lineID)
        XCTAssertEqual(lineIDs.count, 3)
        XCTAssertEqual(lineIDs[0], lineIDs[1])
        XCTAssertGreaterThan(lineIDs[2], lineIDs[1])
    }
}
