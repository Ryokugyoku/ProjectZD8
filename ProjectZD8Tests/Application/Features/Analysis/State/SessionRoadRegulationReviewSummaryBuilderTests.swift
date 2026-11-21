import Foundation
import XCTest
@testable import ProjectZD8

/// 種類ごとのまとめ(通過した件数と結果ごとの件数)を作る規則を検証します(設計書 §3.4 Summaries、§7 TC1b)。
@MainActor
final class SessionRoadRegulationReviewSummaryBuilderTests: XCTestCase {
    /// 値の短い名前です。
    private typealias Values = SessionRoadRegulationReviewTestValues
    /// 検証対象です。
    private let builder = SessionRoadRegulationReviewSummaryBuilder()

    /// 責務: 行が無くても4種類を種類の順に返し、どれも total 0・counts 空であることを確かめます。
    func testNoRowsGiveFourEmptySummaries() {
        let summaries = builder.summaries(for: [])

        XCTAssertEqual(summaries.map(\.kind), [.speedLimit, .stop, .oneWay, .slowDown])
        XCTAssertEqual(summaries.map(\.total), [0, 0, 0, 0])
        XCTAssertTrue(summaries.allSatisfy { $0.counts.isEmpty })
    }

    /// 責務: 題名のキーが `road_regulation.kind.*` で、id が種類であることを確かめます。
    func testTitleKeysAndIdentifiers() {
        let summaries = builder.summaries(for: [])
        let expected: [String] = [
            "road_regulation.kind.speed_limit", "road_regulation.kind.stop", "road_regulation.kind.one_way", "road_regulation.kind.slow_down"
        ]

        XCTAssertEqual(summaries.map(\.titleKey), expected)
        XCTAssertEqual(summaries.map(\.id), [.speedLimit, .stop, .oneWay, .slowDown])
    }

    /// 責務: 1種類だけに行がある時、その種類の total が行数で、他の3種類は total 0 であることを確かめます。
    func testOnlyOneKindHasRows() {
        let rows = [
            Values.row(id: 0, kind: .stop, outcome: .compliant),
            Values.row(id: 1, kind: .stop, outcome: .possibleIssue)
        ]

        let summaries = builder.summaries(for: rows)

        XCTAssertEqual(summaries.map(\.total), [0, 2, 0, 0])
        XCTAssertEqual(summaries.map(\.counts.count), [0, 2, 0, 0])
    }

    /// 責務: counts が、行の順でなく結果の allCases の順に並び、件数0の結果を含まないことを確かめます。
    func testCountsFollowOutcomeOrderWithoutZeros() throws {
        let rows = [
            Values.row(id: 0, kind: .speedLimit, outcome: .unregulated),
            Values.row(id: 1, kind: .speedLimit, outcome: .compliant),
            Values.row(id: 2, kind: .speedLimit, outcome: .possibleIssue),
            Values.row(id: 3, kind: .speedLimit, outcome: .compliant),
            Values.row(id: 4, kind: .speedLimit, outcome: .unregulated),
            Values.row(id: 5, kind: .speedLimit, outcome: .unregulated)
        ]

        let speed = try XCTUnwrap(builder.summaries(for: rows).first)

        XCTAssertEqual(speed.total, 6)
        XCTAssertEqual(speed.counts.map(\.outcome), [.possibleIssue, .compliant, .unregulated])
        XCTAssertEqual(speed.counts.map(\.count), [1, 2, 3])
        XCTAssertEqual(speed.counts.map(\.id), [.possibleIssue, .compliant, .unregulated])
    }

    /// 責務: 件数のラベルのキーと色の分類が、種類と結果の組み合わせの表どおりであることを確かめます。
    func testCountLabelsAndCategoriesFollowTable() throws {
        let rows = [
            Values.row(id: 0, kind: .slowDown, outcome: .observedOnly),
            Values.row(id: 1, kind: .slowDown, outcome: .undeterminable),
            Values.row(id: 2, kind: .oneWay, outcome: .possibleIssue)
        ]

        let summaries = builder.summaries(for: rows)
        let slowDown = try XCTUnwrap(summaries.last)
        let oneWay = try XCTUnwrap(summaries.first { $0.kind == .oneWay })

        XCTAssertEqual(slowDown.counts.map(\.labelKey), ["analysis.road_regulation.outcome.undetermined", "road_regulation.verdict.slow_down.observed"])
        XCTAssertEqual(slowDown.counts.map(\.category), [.tone(.unknown), .tone(.neutral)])
        XCTAssertEqual(oneWay.counts.map(\.labelKey), ["road_regulation.verdict.one_way.possible_wrong_way"])
        XCTAssertEqual(oneWay.counts.map(\.category), [.tone(.caution)])
    }

    /// 責務: 4種類に行がある時、種類ごとの total が行数どおりであることを確かめます。
    func testTotalsPerKind() {
        let rows = [
            Values.row(id: 0, kind: .slowDown, outcome: .observedOnly),
            Values.row(id: 1, kind: .speedLimit, outcome: .compliant),
            Values.row(id: 2, kind: .oneWay, outcome: .compliant),
            Values.row(id: 3, kind: .speedLimit, outcome: .compliant),
            Values.row(id: 4, kind: .stop, outcome: .compliant),
            Values.row(id: 5, kind: .slowDown, outcome: .observedOnly),
            Values.row(id: 6, kind: .slowDown, outcome: .observedOnly)
        ]

        XCTAssertEqual(builder.summaries(for: rows).map(\.total), [2, 1, 1, 3])
    }
}
