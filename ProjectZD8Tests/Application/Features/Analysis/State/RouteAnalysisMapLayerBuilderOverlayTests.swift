import Foundation
import XCTest
@testable import ProjectZD8

/// 重ね合わせ(軌跡の区間 → 分類)を受け取った時の地図の層を検証します(設計書 §1-4、§2.2、§3.4)。
///
@MainActor
final class RouteAnalysisMapLayerBuilderOverlayTests: XCTestCase {
    private typealias Fixtures = RouteAnalysisRouteTimelineFixtures

    /// 検証対象です。
    private let builder = RouteAnalysisMapLayerBuilder()
    /// 東へ 100 m ずつ・1秒おきの10点の時間の軸です。
    private let timeline = Fixtures.timeline(segments: [(0..<10).map { Double($0) * 100 }])
    /// 重ね合わせの凡例です。
    private let legend = [RouteAnalysisLegendEntry(id: 0, category: .tone(.caution), text: "caution")]

    /// 重ね合わせを作ります。
    ///
    /// 責務: 指定の範囲と強調の時刻の範囲を持つ重ね合わせを返します。
    /// - Parameters:
    ///   - runs: 連番の範囲と分類。
    ///   - highlights: 強調する時刻の範囲。
    /// - Returns: 色分けの指定。
    private func overlay(_ runs: [RouteAnalysisColorRun], highlights: [ClosedRange<Date>] = []) -> RouteAnalysisColoring {
        .overlay(RouteAnalysisOverlay(id: "test", titleKey: "test.overlay", runs: runs, legend: legend, highlightedTimeRanges: highlights))
    }

    /// 責務: 範囲の点を始点とする辺が、範囲の分類の線になることを確かめます。
    func testRunCategoryIsDrawn() {
        let runs = [RouteAnalysisColorRun(sequenceRange: 3...5, category: .tone(.critical))]

        let layers = builder.layers(timeline: timeline, coloring: overlay(runs))

        let expected = (3...6).map { timeline.points[$0].coordinate }
        XCTAssertEqual(layers.lines.first { $0.category == .tone(.critical) && !$0.isEmphasized }?.coordinates, expected)
    }

    /// 責務: 重ね合わせでは、10 m の1辺(範囲が1点)でも短い区間の併合をせずに残すことを確かめます。
    func testOverlayDoesNotMergeShortRuns() {
        let short = Fixtures.timeline(segments: [[0, 100, 110, 210]])
        let runs = [RouteAnalysisColorRun(sequenceRange: 1...1, category: .tone(.caution))]

        let layers = builder.layers(timeline: short, coloring: overlay(runs))

        let expected = [short.points[1].coordinate, short.points[2].coordinate]
        XCTAssertEqual(layers.lines.first { $0.category == .tone(.caution) }?.coordinates, expected)
    }

    /// 責務: 凡例が重ね合わせの凡例そのものになることを確かめます。
    func testLegendIsOverlayLegend() {
        let layers = builder.layers(timeline: timeline, coloring: overlay([]))

        XCTAssertEqual(layers.legend, legend)
    }

    /// 責務: 強調の時刻の範囲があれば、その範囲の点を結ぶ強調の線が、ふだんの線に加えて足されることを確かめます。
    func testHighlightRangesAddEmphasizedLines() {
        let highlights = [Fixtures.date(2)...Fixtures.date(4)]

        let layers = builder.layers(timeline: timeline, coloring: overlay([], highlights: highlights))

        let expected = (2...4).map { timeline.points[$0].coordinate }
        XCTAssertEqual(layers.lines.filter(\.isEmphasized).map(\.coordinates), [expected])
        XCTAssertFalse(layers.lines.filter { !$0.isEmphasized }.isEmpty)
    }

    /// 責務: 強調の線を足しても、線の ID が重ならないことを確かめます。
    func testLineIDsAreUniqueWithHighlights() {
        let runs = [RouteAnalysisColorRun(sequenceRange: 2...4, category: .tone(.positive))]
        let highlights = [Fixtures.date(1)...Fixtures.date(3), Fixtures.date(6)...Fixtures.date(8)]

        let layers = builder.layers(timeline: timeline, coloring: overlay(runs, highlights: highlights))

        XCTAssertEqual(layers.lines.filter(\.isEmphasized).count, 2)
        XCTAssertEqual(Set(layers.lines.map(\.id)).count, layers.lines.count)
    }

    /// 責務: 重ね合わせでも、出発と到着の印と範囲が付くことを確かめます。
    func testOverlayKeepsMarkersAndBounds() {
        let layers = builder.layers(timeline: timeline, coloring: overlay([]))

        XCTAssertEqual(layers.markers.first { $0.endpoint == .start }?.coordinate, timeline.points[0].coordinate)
        XCTAssertEqual(layers.markers.first { $0.endpoint == .end }?.coordinate, timeline.points[9].coordinate)
        XCTAssertEqual(layers.bounds, GeoBoundingBox(enclosing: timeline.points.map(\.coordinate)))
    }

    /// 責務: 範囲から外れた点の辺は base の線になることを確かめます。
    func testPointsOutsideRunsAreBase() {
        let runs = [RouteAnalysisColorRun(sequenceRange: 3...5, category: .tone(.critical))]

        let layers = builder.layers(timeline: timeline, coloring: overlay(runs))

        XCTAssertEqual(layers.lines.first { $0.category == .base }?.coordinates, (0...3).map { timeline.points[$0].coordinate })
        XCTAssertEqual(Set(layers.lines.map(\.category)), [.base, .tone(.critical)])
    }

    /// 責務: 範囲に入る点が1つ以上あれば一致あり、1つも無ければ一致なしになることを確かめます。
    func testMatchedValuesReflectRunCoverage() {
        let inside = builder.layers(timeline: timeline, coloring: overlay([RouteAnalysisColorRun(sequenceRange: 9...20, category: .tone(.neutral))]))
        let outside = builder.layers(timeline: timeline, coloring: overlay([RouteAnalysisColorRun(sequenceRange: 50...60, category: .tone(.neutral))]))

        XCTAssertTrue(inside.hasMatchedValues)
        XCTAssertFalse(outside.hasMatchedValues)
    }

    /// 責務: 強調の線の ID が、色の線の ID より後ろに付くことを確かめます。
    func testHighlightIDsFollowColorLineIDs() throws {
        let runs = [RouteAnalysisColorRun(sequenceRange: 2...4, category: .tone(.positive))]

        let layers = builder.layers(timeline: timeline, coloring: overlay(runs, highlights: [Fixtures.date(1)...Fixtures.date(3)]))

        let colorMax = try XCTUnwrap(layers.lines.filter { !$0.isEmphasized }.map(\.id).max())
        let highlightMin = try XCTUnwrap(layers.lines.filter(\.isEmphasized).map(\.id).min())
        XCTAssertGreaterThan(highlightMin, colorMax)
    }

    /// 責務: 強調の線があっても、線の点の合計が点数の上限以下に収まることを確かめます。
    func testPointBudgetIncludesHighlights() {
        let small = RouteAnalysisMapLayerBuilder(pointBudget: 40)
        let zigzag = Fixtures.zigzagTimeline(count: 300)

        let layers = small.layers(timeline: zigzag, coloring: overlay([], highlights: [Fixtures.date(0)...Fixtures.date(10)]))

        XCTAssertFalse(layers.lines.filter(\.isEmphasized).isEmpty)
        XCTAssertLessThanOrEqual(layers.lines.reduce(0) { $0 + $1.coordinates.count }, 40)
    }
}
