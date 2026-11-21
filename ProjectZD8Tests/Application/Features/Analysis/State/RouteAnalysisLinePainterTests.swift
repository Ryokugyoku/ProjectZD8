import Foundation
import XCTest
@testable import ProjectZD8

/// 点ごとの色の分類から、地図に描く線をまとめる規則を検証します(設計書 §3.4 `lines`)。
///
/// 辺 (i→i+1) の分類は点 i の分類です。短い区間の併合は無効にし、点数の上限は十分大きくして、まとめ方だけを確かめます。
@MainActor
final class RouteAnalysisLinePainterTests: XCTestCase {
    private typealias Fixtures = RouteAnalysisRouteTimelineFixtures

    /// 検証対象です。
    private let painter = RouteAnalysisLinePainter()

    /// 線を描きます。
    ///
    /// 責務: 併合なし・上限 5,000 点で、時間の軸と分類から線を作ります。
    /// - Parameters:
    ///   - timeline: 時間の軸。
    ///   - categories: 点ごとの分類。
    /// - Returns: 線。
    private func lines(_ timeline: RouteAnalysisTimeline, _ categories: [RouteAnalysisColorCategory]) -> [RouteAnalysisMapLine] {
        painter.lines(timeline: timeline, categories: categories, mergesShortRuns: false, pointBudget: 5_000)
    }

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

    /// 責務: 分類が一様なら、区間ごとに全点を持つ線が1本ずつできることを確かめます。
    func testUniformCategoryGivesOneLinePerSegment() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200], [1_000, 1_100]])

        let result = lines(timeline, Array(repeating: .base, count: 5))

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.coordinates)), [coordinates(timeline, 0...2), coordinates(timeline, 3...4)])
        XCTAssertTrue(result.allSatisfy { $0.category == .base && !$0.isEmphasized })
    }

    /// 責務: 点 k で分類が変わると、点 k を両方に含む2本の線になることを確かめます。
    func testCategoryChangeSharesBoundaryPoint() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200, 300, 400]])

        let result = lines(timeline, [.ramp(step: 0), .ramp(step: 0), .ramp(step: 0), .ramp(step: 1), .ramp(step: 1)])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first { $0.category == .ramp(step: 0) }?.coordinates, coordinates(timeline, 0...3))
        XCTAssertEqual(result.first { $0.category == .ramp(step: 1) }?.coordinates, coordinates(timeline, 3...4))
    }

    /// 責務: 区間の最後の点の分類は辺を持たないので、線を増やさないことを確かめます。
    func testLastPointCategoryDoesNotStartLine() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200]])

        let result = lines(timeline, [.ramp(step: 0), .ramp(step: 0), .ramp(step: 3)])

        XCTAssertEqual(result.map(\.category), [.ramp(step: 0)])
        XCTAssertEqual(result.first?.coordinates, coordinates(timeline, 0...2))
    }

    /// 責務: 点が1つの区間は線を描かないことを確かめます。
    func testSinglePointSegmentIsNotDrawn() {
        let timeline = Fixtures.timeline(segments: [[0], [100, 200]])

        let result = lines(timeline, Array(repeating: .base, count: 3))

        XCTAssertEqual(result.map(\.coordinates), [coordinates(timeline, 1...2)])
    }

    /// 責務: 分類が同じでも、ルートの切れ目をまたいで線をつながないことを確かめます。
    func testLinesDoNotBridgeSegments() {
        let timeline = Fixtures.timeline(segments: [[0, 100], [200, 300]])

        let result = lines(timeline, Array(repeating: .ramp(step: 2), count: 4))

        XCTAssertEqual(Set(result.map(\.coordinates)), [coordinates(timeline, 0...1), coordinates(timeline, 2...3)])
    }

    /// 責務: 概略の区間の線だけが破線の印(`isApproximate`)を持つことを確かめます。
    func testApproximateSegmentMarksLine() {
        let timeline = Fixtures.timeline(segments: [[0, 100], [200, 300]], precisions: [.precise, .approximate])

        let result = lines(timeline, Array(repeating: .base, count: 4))

        XCTAssertEqual(result.first { $0.coordinates == coordinates(timeline, 0...1) }?.isApproximate, false)
        XCTAssertEqual(result.first { $0.coordinates == coordinates(timeline, 2...3) }?.isApproximate, true)
    }

    /// 責務: 値なしの分類も、それ自体の線として描くことを確かめます。
    func testNoValueRunIsItsOwnLine() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200]])

        let result = lines(timeline, [.noValue, .ramp(step: 1), .ramp(step: 1)])

        XCTAssertEqual(result.first { $0.category == .noValue }?.coordinates, coordinates(timeline, 0...1))
        XCTAssertEqual(result.first { $0.category == .ramp(step: 1) }?.coordinates, coordinates(timeline, 1...2))
    }

    /// 責務: 線の ID が 0 からの連番で、強調の印を持たないことを確かめます。
    func testLineIDsAreUnique() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200, 300], [1_000, 1_100]])

        let result = lines(timeline, [.base, .noValue, .base, .base, .ramp(step: 4), .ramp(step: 4)])

        XCTAssertEqual(result.map(\.id).sorted(), [0, 1, 2, 3])
        XCTAssertTrue(result.allSatisfy { !$0.isEmphasized })
    }

    /// 責務: 分類が点の数より少ない時、足りない点は値なしとして描くことを確かめます。
    func testMissingCategoriesAreNoValue() {
        let timeline = Fixtures.timeline(segments: [[0, 100, 200, 300]])

        let result = lines(timeline, [.ramp(step: 1), .ramp(step: 1)])

        XCTAssertEqual(result.first { $0.category == .ramp(step: 1) }?.coordinates, coordinates(timeline, 0...2))
        XCTAssertEqual(result.first { $0.category == .noValue }?.coordinates, coordinates(timeline, 2...3))
    }

    /// 責務: 点の無い時間の軸からは線ができないことを確かめます。
    func testEmptyTimelineGivesNoLines() {
        XCTAssertEqual(lines(Fixtures.timeline(segments: []), []), [])
    }
}
