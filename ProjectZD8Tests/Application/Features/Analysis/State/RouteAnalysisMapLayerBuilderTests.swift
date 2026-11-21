import Foundation
import XCTest
@testable import ProjectZD8

/// 時間の軸と色分けの指定から、地図の層(線・印・範囲・凡例・値の有無)を作る規則を検証します(設計書 §2.2〜§2.4、§3.4)。
///
/// 色なしと指標の色分けを確かめます。重ね合わせは `RouteAnalysisMapLayerBuilderOverlayTests` で確かめます。
@MainActor
final class RouteAnalysisMapLayerBuilderTests: XCTestCase {
    private typealias Fixtures = RouteAnalysisRouteTimelineFixtures

    /// ロケールを固定した検証対象です。
    private let builder = RouteAnalysisMapLayerBuilder(legendBuilder: RouteAnalysisLegendBuilder(locale: Locale(identifier: "en_US")))
    /// 東へ 100 m ずつ・1秒おきの10点の時間の軸です。
    private let timeline = Fixtures.timeline(segments: [(0..<10).map { Double($0) * 100 }])

    /// 指定の秒にだけ値を持つ車速の列を作ります。
    ///
    /// 責務: 秒と値の組から、車速の値の列を返します。
    /// - Parameters:
    ///   - samples: 秒と値の組。
    ///   - unit: 単位。
    /// - Returns: 値の列。
    private func speed(_ samples: [(seconds: TimeInterval, value: Double)], unit: String? = "km/h") -> RouteAnalysisColoring {
        .metric(.vehicleSpeed, RouteAnalysisValueSeriesFixtures.series(samples, unit: unit))
    }

    /// 責務: 点の無い時間の軸では、線も印も範囲も無いことを確かめます。
    func testEmptyTimelineHasNoGeometry() {
        let layers = builder.layers(timeline: Fixtures.timeline(segments: []), coloring: .none)

        XCTAssertEqual(layers.lines, [])
        XCTAssertEqual(layers.markers, [])
        XCTAssertNil(layers.bounds)
    }

    /// 責務: 出発の印が最初の区間の最初の点に、到着の印が最後の区間の最後の点に付くことを確かめます。
    func testMarkersAtStartAndEnd() {
        let twoSegments = Fixtures.timeline(segments: [[0, 100, 200], [1_000, 1_100]])

        let layers = builder.layers(timeline: twoSegments, coloring: .none)

        XCTAssertEqual(layers.markers.count, 2)
        XCTAssertEqual(layers.markers.first { $0.endpoint == .start }?.coordinate, twoSegments.points[0].coordinate)
        XCTAssertEqual(layers.markers.first { $0.endpoint == .end }?.coordinate, twoSegments.points[4].coordinate)
        XCTAssertEqual(layers.markers.first { $0.endpoint == .start }?.id, 0)
        XCTAssertEqual(layers.markers.first { $0.endpoint == .end }?.id, 1)
    }

    /// 責務: 点が1つだけなら、出発の印だけが付くことを確かめます。
    func testSinglePointHasOnlyStartMarker() {
        let single = Fixtures.timeline(segments: [[0]])

        let layers = builder.layers(timeline: single, coloring: .none)

        XCTAssertEqual(layers.markers, [RouteAnalysisMapMarker(id: 0, coordinate: single.points[0].coordinate, endpoint: .start)])
    }

    /// 責務: 範囲が全点を囲む外接矩形になることを確かめます。
    func testBoundsEncloseAllPoints() {
        let layers = builder.layers(timeline: timeline, coloring: .none)

        XCTAssertEqual(layers.bounds, GeoBoundingBox(enclosing: timeline.points.map(\.coordinate)))
    }

    /// 責務: 色なしでは、全点を結ぶ base の線になり、凡例も値なしの辺も無いことを確かめます。
    func testNoColoringGivesBaseLines() {
        let layers = builder.layers(timeline: timeline, coloring: .none)

        XCTAssertFalse(layers.lines.isEmpty)
        XCTAssertTrue(layers.lines.allSatisfy { $0.category == .base && !$0.isEmphasized })
        XCTAssertEqual(layers.lines.reduce(0) { $0 + $1.coordinates.count }, 10)
        XCTAssertEqual(layers.legend, [])
        XCTAssertFalse(layers.hasNoValueEdges)
        XCTAssertFalse(layers.hasMatchedValues)
    }

    /// 責務: 時刻の合う値が1つも無ければ、すべて値なしの線になり、一致なし・値なしの辺あり・凡例に値なし、になることを確かめます。
    func testMetricWithoutMatchesIsAllNoValue() {
        let layers = builder.layers(timeline: timeline, coloring: speed([(100, 50), (200, 50)]))

        XCTAssertFalse(layers.lines.isEmpty)
        XCTAssertTrue(layers.lines.allSatisfy { $0.category == .noValue })
        XCTAssertFalse(layers.hasMatchedValues)
        XCTAssertTrue(layers.hasNoValueEdges)
        XCTAssertTrue(layers.legend.contains { $0.category == .noValue })
    }

    /// 責務: 全点に値が合えば、境界の区分の色の線になり、値なしの辺が無く、凡例が区分の5項目だけになることを確かめます。
    func testMatchedValuesColorByBands() {
        let samples: [(seconds: TimeInterval, value: Double)] = (0..<10).map { (TimeInterval($0), $0 < 5 ? 10 : 50) }

        let layers = builder.layers(timeline: timeline, coloring: speed(samples))

        XCTAssertEqual(Set(layers.lines.map(\.category)), [.ramp(step: 0), .ramp(step: 2)])
        XCTAssertTrue(layers.hasMatchedValues)
        XCTAssertFalse(layers.hasNoValueEdges)
        XCTAssertEqual(layers.legend.map(\.category), (0..<5).map { .ramp(step: $0) })
    }

    /// 責務: 一部の点だけ値が合えば、区分の色と値なしの線が混ざり、凡例に値なしが加わることを確かめます。
    func testPartialMatchesMixNoValue() {
        let samples: [(seconds: TimeInterval, value: Double)] = (0..<5).map { (TimeInterval($0), 90) }

        let layers = builder.layers(timeline: timeline, coloring: speed(samples))

        XCTAssertEqual(Set(layers.lines.map(\.category)), [.ramp(step: 4), .noValue])
        XCTAssertTrue(layers.hasMatchedValues)
        XCTAssertTrue(layers.hasNoValueEdges)
        XCTAssertTrue(layers.legend.contains { $0.category == .noValue })
    }

    /// 責務: 凡例の単位が、列の単位を優先し、無ければ指標の既定の単位になることを確かめます。
    func testLegendUnitPrefersSeriesUnit() {
        let samples: [(seconds: TimeInterval, value: Double)] = (0..<10).map { (TimeInterval($0), 30) }

        let withUnit = builder.layers(timeline: timeline, coloring: speed(samples, unit: "mph")).legend
        let withoutUnit = builder.layers(timeline: timeline, coloring: speed(samples, unit: nil)).legend

        let rampWithUnit = withUnit.filter { $0.category != .noValue }
        let rampWithoutUnit = withoutUnit.filter { $0.category != .noValue }
        XCTAssertEqual(rampWithUnit.count, 5)
        XCTAssertEqual(rampWithoutUnit.count, 5)
        XCTAssertTrue(rampWithUnit.allSatisfy { $0.text.contains("mph") }, "\(rampWithUnit.map(\.text))")
        XCTAssertTrue(rampWithoutUnit.allSatisfy { $0.text.contains("km/h") }, "\(rampWithoutUnit.map(\.text))")
    }

    /// 責務: 指標の色分けでは、10 m の短い色の区間が併合されて残らないことを確かめます。
    func testMetricColoringMergesShortRuns() {
        let short = Fixtures.timeline(segments: [[0, 100, 110, 210]])
        let samples: [(seconds: TimeInterval, value: Double)] = [(0, 10), (1, 50), (2, 10), (3, 10)]

        let layers = builder.layers(timeline: short, coloring: speed(samples))

        XCTAssertFalse(layers.lines.contains { $0.category == .ramp(step: 2) })
        XCTAssertTrue(layers.lines.contains { $0.category == .ramp(step: 0) })
    }

    /// 責務: 線の点の合計が、初期化で渡した点数の上限以下に収まることを確かめます。
    func testPointBudgetLimitsLines() {
        let small = RouteAnalysisMapLayerBuilder(pointBudget: 40)

        let layers = small.layers(timeline: Fixtures.zigzagTimeline(count: 300), coloring: .none)

        XCTAssertFalse(layers.lines.isEmpty)
        XCTAssertLessThanOrEqual(layers.lines.reduce(0) { $0 + $1.coordinates.count }, 40)
    }
}
