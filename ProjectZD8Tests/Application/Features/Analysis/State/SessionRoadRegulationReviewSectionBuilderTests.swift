import Foundation
import XCTest
@testable import ProjectZD8

/// 種類ごとの一覧(絞り込み・空の時の文言・行が見えるか)を作る規則を検証します(設計書 §3.4 Sections、§7 TC1b)。
@MainActor
final class SessionRoadRegulationReviewSectionBuilderTests: XCTestCase {
    /// 値の短い名前です。
    private typealias Values = SessionRoadRegulationReviewTestValues
    /// 検証対象です。
    private let builder = SessionRoadRegulationReviewSectionBuilder()
    /// 種類の通過が0件の時の文言キーです。
    private let emptyKind = "analysis.road_regulation.list.empty_kind"
    /// 絞り込みで0件になった時の文言キーです。
    private let emptyAttention = "analysis.road_regulation.list.empty_attention"

    /// 最高速度に5つの結果を1件ずつ、一時停止に良好を1件持つ行です。
    ///
    /// 責務: 絞り込みで消える結果と残る結果をそろえた入力を、id の順でない並びで返します。
    /// - Returns: 行。
    private func mixedRows() -> [SessionRoadRegulationReviewRow] {
        [
            Values.row(id: 4, kind: .speedLimit, outcome: .possibleIssue),
            Values.row(id: 0, kind: .speedLimit, outcome: .compliant),
            Values.row(id: 3, kind: .speedLimit, outcome: .undeterminable),
            Values.row(id: 1, kind: .speedLimit, outcome: .unregulated),
            Values.row(id: 2, kind: .speedLimit, outcome: .observedOnly),
            Values.row(id: 5, kind: .stop, outcome: .compliant)
        ]
    }

    /// 責務: 行が無くても4件を種類の順に返し、題名のキー・id・件数0・種類が空の文言であることを確かめます。
    func testNoRowsGiveFourEmptySections() {
        let sections = builder.sections(for: [], filter: .attention)
        let titles: [String] = [
            "road_regulation.kind.speed_limit", "road_regulation.kind.stop", "road_regulation.kind.one_way", "road_regulation.kind.slow_down"
        ]

        XCTAssertEqual(sections.map(\.kind), [.speedLimit, .stop, .oneWay, .slowDown])
        XCTAssertEqual(sections.map(\.id), [.speedLimit, .stop, .oneWay, .slowDown])
        XCTAssertEqual(sections.map(\.titleKey), titles)
        XCTAssertEqual(sections.map(\.totalCount), [0, 0, 0, 0])
        XCTAssertEqual(sections.map(\.emptyMessageKey), [emptyKind, emptyKind, emptyKind, emptyKind])
    }

    /// 責務: 「確認が必要な区間」では良好・指定なし・徐行の通過が消え、possibleIssue と undeterminable が id の昇順で残ることを確かめます。
    func testAttentionKeepsIssueAndUndeterminableInIDOrder() throws {
        let speed = try XCTUnwrap(builder.sections(for: mixedRows(), filter: .attention).first)

        XCTAssertEqual(speed.rows.map(\.id), [3, 4])
        XCTAssertEqual(speed.totalCount, 5)
        XCTAssertNil(speed.emptyMessageKey)
    }

    /// 責務: 「すべて」では全件を id の昇順で残し、totalCount が絞り込み前の件数であることを確かめます。
    func testAllKeepsEveryRowInIDOrder() throws {
        let speed = try XCTUnwrap(builder.sections(for: mixedRows(), filter: .all).first)

        XCTAssertEqual(speed.rows.map(\.id), [0, 1, 2, 3, 4])
        XCTAssertEqual(speed.totalCount, 5)
    }

    /// 責務: 空の時の文言の3分岐(通過0件 → empty_kind、絞り込みで0件 → empty_attention、行あり → nil)を確かめます。
    func testEmptyMessageBranches() {
        let sections = builder.sections(for: mixedRows(), filter: .attention)

        XCTAssertEqual(sections.map(\.emptyMessageKey), [nil, emptyAttention, emptyKind, emptyKind])
        XCTAssertEqual(sections.map(\.totalCount), [5, 1, 0, 0])
        XCTAssertEqual(sections.dropFirst().first?.rows, [])
    }

    /// 責務: 「すべて」で行がある種類は文言が nil、通過0件の種類は empty_kind のままであることを確かめます。
    func testAllFilterEmptyMessages() {
        let sections = builder.sections(for: mixedRows(), filter: .all)

        XCTAssertEqual(sections.map(\.emptyMessageKey), [nil, nil, emptyKind, emptyKind])
    }

    /// 責務: 行が種類ごとに振り分けられ、他の種類の行が混ざらないことを確かめます。
    func testRowsAreGroupedByKind() {
        let sections = builder.sections(for: mixedRows(), filter: .all)

        XCTAssertEqual(sections.dropFirst().first?.rows.map(\.id), [5])
        XCTAssertEqual(sections.first?.rows.map(\.kind), [.speedLimit, .speedLimit, .speedLimit, .speedLimit, .speedLimit])
    }

    /// 責務: `isVisible` が、見えている行で true、絞り込みで消えた行と存在しない id で false であることを確かめます。
    func testIsVisible() {
        let sections = builder.sections(for: mixedRows(), filter: .attention)

        XCTAssertTrue(builder.isVisible(rowID: 4, in: sections))
        XCTAssertTrue(builder.isVisible(rowID: 3, in: sections))
        XCTAssertFalse(builder.isVisible(rowID: 0, in: sections))
        XCTAssertFalse(builder.isVisible(rowID: 5, in: sections))
        XCTAssertFalse(builder.isVisible(rowID: 99, in: sections))
    }

    /// 責務: 一覧が空なら、どの id も見えないことを確かめます。
    func testIsVisibleWithNoSections() {
        XCTAssertFalse(builder.isVisible(rowID: 0, in: []))
    }
}
