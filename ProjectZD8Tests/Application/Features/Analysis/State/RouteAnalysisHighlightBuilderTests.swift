import Foundation
import XCTest
@testable import ProjectZD8

/// 重ね合わせの時刻の範囲から、地図に重ねる強調の線を作る規則を検証します(設計書 §1-4、§3.4 `RouteAnalysisHighlightBuilder`)。
///
/// 点の時刻は基準からの秒で、位置の番号と同じです。
@MainActor
final class RouteAnalysisHighlightBuilderTests: XCTestCase {
    private typealias Fixtures = RouteAnalysisRouteTimelineFixtures

    /// 検証対象です。
    private let builder = RouteAnalysisHighlightBuilder()
    /// 強調の線の最初の ID です。
    private let firstID = 7

    /// 基準からの秒の閉区間を返します。
    ///
    /// 責務: 時刻の範囲を秒で書けるようにします。
    /// - Parameters:
    ///   - start: 始まりの秒。
    ///   - end: 終わりの秒。
    /// - Returns: 時刻の範囲。
    private func range(_ start: TimeInterval, _ end: TimeInterval) -> ClosedRange<Date> {
        Fixtures.date(start)...Fixtures.date(end)
    }

    /// 時間の軸の点の座標を、位置の番号の範囲で返します。
    ///
    /// 責務: 期待する線の座標の列を作ります。
    /// - Parameters:
    ///   - timeline: 時間の軸。
    ///   - indices: 点の位置の範囲。
    /// - Returns: 座標の列。
    private func coordinates(_ timeline: RouteAnalysisTimeline, _ indices: ClosedRange<Int>) -> [GeoCoordinate] {
        indices.map { timeline.points[$0].coordinate }
    }

    /// 責務: 範囲が無ければ強調の線は無いことを確かめます。
    func testNoRangesGiveNoLines() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200]])

        XCTAssertEqual(builder.lines(timeline: timeline, ranges: [], firstID: firstID), [])
    }

    /// 責務: 範囲(両端を含む)の中の点を結ぶ強調の線が1本でき、ID が最初の ID になることを確かめます。
    func testRangeCoversPointsInside() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200, 300, 400, 500]])

        let result = builder.lines(timeline: timeline, ranges: [range(2, 4)], firstID: firstID)

        XCTAssertEqual(result.map(\.coordinates), [coordinates(timeline, 2...4)])
        XCTAssertEqual(result.map(\.id), [firstID])
        XCTAssertEqual(result.map(\.isEmphasized), [true])
        XCTAssertEqual(result.map(\.category), [.base])
    }

    /// 責務: 範囲の中の点が区間に1つだけなら、その区間からは線ができないことを確かめます。
    func testSinglePointInRangeGivesNoLine() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200]])

        XCTAssertEqual(builder.lines(timeline: timeline, ranges: [range(0.5, 1.5)], firstID: firstID), [])
    }

    /// 責務: 間引かずに、範囲の中の点をすべて残すことを確かめます。
    func testHighlightIsNotSimplified() {
        let timeline = Fixtures.timeline(segments: [(0..<50).map { Double($0) * 10 }])

        let result = builder.lines(timeline: timeline, ranges: [range(0, 49)], firstID: firstID)

        XCTAssertEqual(result.map(\.coordinates), [coordinates(timeline, 0...49)])
    }

    /// 責務: 範囲の外の点(範囲の端より 0.5 秒外)を含めないことを確かめます。
    func testPointsOutsideRangeAreExcluded() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200, 300, 400, 500]])

        let result = builder.lines(timeline: timeline, ranges: [range(1.5, 3.5)], firstID: firstID)

        XCTAssertEqual(result.map(\.coordinates), [coordinates(timeline, 2...3)])
    }

    /// 責務: 範囲がルートの切れ目をまたぐ時は、区間ごとの別の線になり、ID が最初の ID から重ならずに付くことを確かめます。
    func testRangeAcrossSegmentGapGivesSeparateLines() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200], [1_000, 1_100, 1_200]])

        let result = builder.lines(timeline: timeline, ranges: [range(1, 4)], firstID: firstID)

        XCTAssertEqual(Set(result.map(\.coordinates)), [coordinates(timeline, 1...2), coordinates(timeline, 3...4)])
        XCTAssertEqual(Set(result.map(\.id)), [firstID, firstID + 1])
        XCTAssertTrue(result.allSatisfy(\.isEmphasized))
    }

    /// 責務: 複数の範囲は、それぞれの強調の線になることを確かめます。
    func testMultipleRangesGiveLinesForEach() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200, 300, 400, 500, 600]])

        let result = builder.lines(timeline: timeline, ranges: [range(0, 1), range(4, 6)], firstID: firstID)

        XCTAssertEqual(Set(result.map(\.coordinates)), [coordinates(timeline, 0...1), coordinates(timeline, 4...6)])
        XCTAssertEqual(Set(result.map(\.id)).count, 2)
        XCTAssertTrue(result.allSatisfy { $0.id >= firstID })
    }

    /// 責務: 点を含まない範囲からは線ができないことを確かめます。
    func testRangeWithoutPointsGivesNoLines() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200]])

        XCTAssertEqual(builder.lines(timeline: timeline, ranges: [range(10, 20)], firstID: firstID), [])
    }

    /// 責務: 概略の区間の強調の線は、破線の印(`isApproximate`)を持つことを確かめます。
    func testApproximateSegmentHighlightIsApproximate() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200]], precisions: [.approximate])

        let result = builder.lines(timeline: timeline, ranges: [range(0, 2)], firstID: firstID)

        XCTAssertEqual(result.map(\.isApproximate), [true])
    }
}
