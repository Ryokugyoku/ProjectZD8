import Foundation
import XCTest
@testable import ProjectZD8

/// 重ね合わせ(位置の連番の範囲 → 分類)から、点ごとの分類を引く規則を検証します(設計書 §3.4 `categories`)。
@MainActor
final class RouteAnalysisLinePainterCategoryTests: XCTestCase {
    private typealias Fixtures = RouteAnalysisRouteTimelineFixtures

    /// 検証対象です。
    private let painter = RouteAnalysisLinePainter()
    /// 範囲から外れた点の分類です。
    private let fallback = RouteAnalysisColorCategory.base

    /// 連番を指定した時間の軸を作ります。
    ///
    /// 責務: 位置の番号と異なる連番を持つ点を、1区間に 100 m・1 秒おきで並べます。
    /// - Parameter sequences: 点ごとの連番。
    /// - Returns: 時間の軸。
    private func timeline(sequences: [Int64]) -> RouteAnalysisTimeline {
        let points: [RouteAnalysisTimelinePoint] = sequences.enumerated().map { offset, sequence in
            Fixtures.point(index: offset, sequence: sequence, segmentIndex: 0, x: Double(offset) * 100, seconds: TimeInterval(offset))
        }
        return Fixtures.timeline(points: points)
    }

    /// 責務: 連番が範囲に入る点はその範囲の分類、外れる点は代わりの分類になり、結果が点と同じ数・順であることを確かめます。
    func testPointsInsideRunTakeRunCategory() {
        let runs = [RouteAnalysisColorRun(sequenceRange: 20...30, category: .tone(.caution))]

        let result = painter.categories(timeline: timeline(sequences: [10, 20, 25, 30, 40]), runs: runs, fallback: fallback)

        XCTAssertEqual(result, [.base, .tone(.caution), .tone(.caution), .tone(.caution), .base])
    }

    /// 責務: 範囲の両端は含み、その1つ外側は含まないことを確かめます。
    func testRangeBoundsAreInclusive() {
        let runs = [RouteAnalysisColorRun(sequenceRange: 5...7, category: .tone(.critical))]

        let result = painter.categories(timeline: timeline(sequences: [4, 5, 7, 8]), runs: runs, fallback: fallback)

        XCTAssertEqual(result, [.base, .tone(.critical), .tone(.critical), .base])
    }

    /// 責務: 範囲が重なる時は、配列の先にある範囲の分類が優先されることを確かめます。
    func testEarlierRunWinsOnOverlap() {
        let runs = [
            RouteAnalysisColorRun(sequenceRange: 2...3, category: .tone(.positive)),
            RouteAnalysisColorRun(sequenceRange: 1...4, category: .tone(.critical))
        ]

        let result = painter.categories(timeline: timeline(sequences: [1, 2, 3, 4]), runs: runs, fallback: fallback)

        XCTAssertEqual(result, [.tone(.critical), .tone(.positive), .tone(.positive), .tone(.critical)])
    }

    /// 責務: 範囲が無ければ、すべての点が代わりの分類になることを確かめます。
    func testNoRunsGiveFallbackForAllPoints() {
        let result = painter.categories(timeline: timeline(sequences: [0, 1, 2]), runs: [], fallback: .noValue)

        XCTAssertEqual(result, [.noValue, .noValue, .noValue])
    }

    /// 責務: 点の無い時間の軸では空になることを確かめます。
    func testEmptyTimelineGivesEmptyCategories() {
        let runs = [RouteAnalysisColorRun(sequenceRange: 0...10, category: .tone(.neutral))]

        XCTAssertEqual(painter.categories(timeline: timeline(sequences: []), runs: runs, fallback: fallback), [])
    }

    /// 責務: 範囲は位置の番号ではなく連番で引くことを確かめます。
    func testRunsMatchSequenceNotIndex() {
        let runs = [RouteAnalysisColorRun(sequenceRange: 1...1, category: .tone(.unknown))]

        let result = painter.categories(timeline: timeline(sequences: [100, 1, 200]), runs: runs, fallback: fallback)

        XCTAssertEqual(result, [.base, .tone(.unknown), .base])
    }

    /// 責務: 範囲の分類が、その点を始点とする辺(点 i → i+1)の色になることを、線へまとめて確かめます。
    func testRunColorsEdgeStartingAtPoint() {
        let route = timeline(sequences: [0, 1, 2, 3])
        let runs = [RouteAnalysisColorRun(sequenceRange: 1...1, category: .tone(.caution))]
        let categories = painter.categories(timeline: route, runs: runs, fallback: fallback)

        let lines = painter.lines(timeline: route, categories: categories, mergesShortRuns: false, pointBudget: 5_000)

        let expected = [route.points[1].coordinate, route.points[2].coordinate]
        XCTAssertEqual(lines.first { $0.category == .tone(.caution) }?.coordinates, expected)
    }
}
