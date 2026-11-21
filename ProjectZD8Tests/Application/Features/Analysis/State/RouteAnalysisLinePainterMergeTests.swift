import Foundation
import XCTest
@testable import ProjectZD8

/// 線をまとめる時の、短い色の区間の併合(30 m 未満)と点数の上限の規則を検証します(設計書 §2.2、§3.4 `lines`)。
///
/// 距離は製品の座標計算と独立な式で置くため、境界はちょうどの値でなく29 m と 31 mで確かめます。
@MainActor
final class RouteAnalysisLinePainterMergeTests: XCTestCase {
    private typealias Fixtures = RouteAnalysisRouteTimelineFixtures

    /// 検証対象です。
    private let painter = RouteAnalysisLinePainter()

    /// 時間の軸の点の座標を、位置の番号の範囲で返します。
    ///
    /// 責務: 期待する線の座標の列を作ります。
    /// - Parameters:
    ///   - timeline: 時間の軸。
    ///   - range: 点の位置の範囲。
    /// - Returns: 座標の列。
    private func coordinates(_ timeline: RouteAnalysisTimeline, _ range: ClosedRange<Int>) -> [GeoCoordinate] {
        range.map { timeline.points[$0].coordinate }
    }

    /// 責務: 途中の 29 m の色の区間が、直前の区間へ併合されることを確かめます。
    func testShortRunMergesIntoPreviousRun() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 129, 229]])
        let categories: [RouteAnalysisColorCategory] = [.ramp(step: 0), .ramp(step: 1), .ramp(step: 2), .ramp(step: 2)]

        let result = painter.lines(timeline: timeline, categories: categories, mergesShortRuns: true, pointBudget: 5_000)

        XCTAssertFalse(result.contains { $0.category == .ramp(step: 1) })
        XCTAssertEqual(result.first { $0.category == .ramp(step: 0) }?.coordinates, coordinates(timeline, 0...2))
        XCTAssertEqual(result.first { $0.category == .ramp(step: 2) }?.coordinates, coordinates(timeline, 2...3))
    }

    /// 責務: 先頭の 29 m の色の区間が、次の区間へ併合されることを確かめます。
    func testShortLeadingRunMergesIntoNextRun() {
        let timeline = Fixtures.timeline(segments: [[0, 29, 129]])
        let categories: [RouteAnalysisColorCategory] = [.ramp(step: 1), .ramp(step: 0), .ramp(step: 0)]

        let result = painter.lines(timeline: timeline, categories: categories, mergesShortRuns: true, pointBudget: 5_000)

        XCTAssertEqual(result.map(\.category), [.ramp(step: 0)])
        XCTAssertEqual(result.first?.coordinates, coordinates(timeline, 0...2))
    }

    /// 責務: 30 m の少し外側(31 m)の色の区間は併合されないことを確かめます。
    func testRunJustLongerThanMinimumIsKept() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 131, 231]])
        let categories: [RouteAnalysisColorCategory] = [.ramp(step: 0), .ramp(step: 1), .ramp(step: 2), .ramp(step: 2)]

        let result = painter.lines(timeline: timeline, categories: categories, mergesShortRuns: true, pointBudget: 5_000)

        XCTAssertEqual(result.first { $0.category == .ramp(step: 1) }?.coordinates, coordinates(timeline, 1...2))
    }

    /// 責務: 先頭の 31 m の色の区間も併合されないことを確かめます。
    func testLeadingRunJustLongerThanMinimumIsKept() {
        let timeline = Fixtures.timeline(segments: [[0, 31, 131]])
        let categories: [RouteAnalysisColorCategory] = [.ramp(step: 1), .ramp(step: 0), .ramp(step: 0)]

        let result = painter.lines(timeline: timeline, categories: categories, mergesShortRuns: true, pointBudget: 5_000)

        XCTAssertEqual(result.first { $0.category == .ramp(step: 1) }?.coordinates, coordinates(timeline, 0...1))
        XCTAssertEqual(result.first { $0.category == .ramp(step: 0) }?.coordinates, coordinates(timeline, 1...2))
    }

    /// 責務: 併合を無効にすると、29 m の色の区間もそのまま残ることを確かめます。
    func testShortRunIsKeptWhenMergingIsDisabled() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 129, 229]])
        let categories: [RouteAnalysisColorCategory] = [.ramp(step: 0), .ramp(step: 1), .ramp(step: 2), .ramp(step: 2)]

        let result = painter.lines(timeline: timeline, categories: categories, mergesShortRuns: false, pointBudget: 5_000)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.first { $0.category == .ramp(step: 1) }?.coordinates, coordinates(timeline, 1...2))
    }

    /// 責務: 線の点の合計が点数の上限以下に収まることを確かめます。
    func testPointBudgetLimitsTotalCoordinates() {
        let timeline = Fixtures.zigzagTimeline(count: 400)
        let categories: [RouteAnalysisColorCategory] = (0..<400).map { .ramp(step: $0 / 100) }

        let result = painter.lines(timeline: timeline, categories: categories, mergesShortRuns: false, pointBudget: 60)

        let total = result.reduce(0) { $0 + $1.coordinates.count }
        XCTAssertLessThanOrEqual(total, 60)
        XCTAssertEqual(Set(result.map(\.category)), [.ramp(step: 0), .ramp(step: 1), .ramp(step: 2), .ramp(step: 3)])
    }

    /// 責務: 間引いても、色の境目の点と区間の両端の点が各線の端に残ることを確かめます。
    func testColorBoundaryPointsSurviveSimplification() throws {
        let timeline = Fixtures.zigzagTimeline(count: 300)
        let categories: [RouteAnalysisColorCategory] = (0..<300).map { .ramp(step: $0 / 100) }

        let result = painter.lines(timeline: timeline, categories: categories, mergesShortRuns: false, pointBudget: 40)

        let first = try XCTUnwrap(result.first { $0.category == .ramp(step: 0) })
        let middle = try XCTUnwrap(result.first { $0.category == .ramp(step: 1) })
        let last = try XCTUnwrap(result.first { $0.category == .ramp(step: 2) })
        XCTAssertLessThan(result.reduce(0) { $0 + $1.coordinates.count }, 300)
        XCTAssertEqual(first.coordinates.first, timeline.points[0].coordinate)
        XCTAssertEqual(first.coordinates.last, timeline.points[100].coordinate)
        XCTAssertEqual(middle.coordinates.first, timeline.points[100].coordinate)
        XCTAssertEqual(middle.coordinates.last, timeline.points[200].coordinate)
        XCTAssertEqual(last.coordinates.first, timeline.points[200].coordinate)
        XCTAssertEqual(last.coordinates.last, timeline.points[299].coordinate)
    }

    /// 責務: 先頭の短い区間を次へ合わせてもまだ短ければ、さらに次の区間へ併合されることを確かめます。
    func testLeadingShortRunsCascadeIntoLaterRun() {
        let timeline = Fixtures.timeline(segments: [[0, 10, 20, 120]])
        let categories: [RouteAnalysisColorCategory] = [.ramp(step: 1), .ramp(step: 2), .ramp(step: 0), .ramp(step: 0)]

        let result = painter.lines(timeline: timeline, categories: categories, mergesShortRuns: true, pointBudget: 5_000)

        XCTAssertEqual(result.map(\.category), [.ramp(step: 0)])
        XCTAssertEqual(result.first?.coordinates, coordinates(timeline, 0...3))
    }

    /// 責務: 区間に色の区間が1つだけなら、短くても(20 m)残ることを確かめます。
    func testOnlyRunInSegmentIsKeptEvenIfShort() {
        let timeline = Fixtures.timeline(segments: [[0, 20]])

        let result = painter.lines(timeline: timeline, categories: [.ramp(step: 3), .ramp(step: 3)], mergesShortRuns: true, pointBudget: 5_000)

        XCTAssertEqual(result.map(\.category), [.ramp(step: 3)])
    }

    /// 責務: 値なしの短い区間(20 m)も併合の対象になることを確かめます。
    func testShortNoValueRunIsMerged() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 120, 220]])
        let categories: [RouteAnalysisColorCategory] = [.ramp(step: 0), .noValue, .ramp(step: 3), .ramp(step: 3)]

        let result = painter.lines(timeline: timeline, categories: categories, mergesShortRuns: true, pointBudget: 5_000)

        XCTAssertFalse(result.contains { $0.category == .noValue })
        XCTAssertEqual(result.first { $0.category == .ramp(step: 0) }?.coordinates, coordinates(timeline, 0...2))
    }

    /// 責務: 併合が有効で端点の合計が上限を超える時は、併合を強めて点の合計を上限以下に収めることを確かめます。
    func testMergingTightensWhenEndpointsExceedBudget() {
        let timeline = Fixtures.timeline(segments: [(0..<20).map { Double($0) * 100 }])
        let categories: [RouteAnalysisColorCategory] = (0..<20).map { .ramp(step: $0 % 2) }

        let result = painter.lines(timeline: timeline, categories: categories, mergesShortRuns: true, pointBudget: 10)

        XCTAssertFalse(result.isEmpty)
        XCTAssertLessThanOrEqual(result.reduce(0) { $0 + $1.coordinates.count }, 10)
    }

    /// 責務: 併合が無効なら、端点の合計が上限を超えても線の本数を減らさないことを確かめます。
    func testLinesAreNotReducedWhenMergingIsDisabled() {
        let timeline = Fixtures.timeline(segments: [(0..<20).map { Double($0) * 100 }])
        let categories: [RouteAnalysisColorCategory] = (0..<20).map { .ramp(step: $0 % 2) }

        let result = painter.lines(timeline: timeline, categories: categories, mergesShortRuns: false, pointBudget: 10)

        XCTAssertEqual(result.count, 19)
    }
}
