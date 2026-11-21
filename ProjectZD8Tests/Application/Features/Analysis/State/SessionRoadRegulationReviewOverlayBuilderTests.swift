import Foundation
import XCTest
@testable import ProjectZD8

/// 段階4へ送る重ね合わせの作り方(作る種類・題名・色分けの run・凡例)を検証します(設計書 §3.4 Overlays、§7 TC1b)。
///
/// 強調の範囲は `SessionRoadRegulationReviewOverlayBuilderHighlightTests` で検証します。
@MainActor
final class SessionRoadRegulationReviewOverlayBuilderTests: XCTestCase {
    /// 値の短い名前です。
    private typealias Values = SessionRoadRegulationReviewTestValues
    /// 文言をキーの `<キー>` に解決する検証対象です。
    private let builder = SessionRoadRegulationReviewOverlayBuilder(localize: SessionRoadRegulationReviewTestValues.bracketLocalize)

    /// 最高速度に4つの結果、id と並びをずらして置いた行です。
    ///
    /// 責務: run の並び(結果の優先 → id の昇順)を確かめる入力を返します。
    /// - Returns: 行。
    private func speedRows() -> [SessionRoadRegulationReviewRow] {
        [
            Values.row(id: 1, kind: .speedLimit, outcome: .compliant, sequences: 0...5),
            Values.row(id: 5, kind: .speedLimit, outcome: .possibleIssue, sequences: 10...20),
            Values.row(id: 3, kind: .speedLimit, outcome: .possibleIssue, sequences: 30...40),
            Values.row(id: 2, kind: .speedLimit, outcome: .unregulated, sequences: 50...60),
            Values.row(id: 4, kind: .speedLimit, outcome: .undeterminable, sequences: 70...80)
        ]
    }

    /// 責務: 行が無ければ重ね合わせを作らないことを確かめます。
    func testNoRowsGiveNoOverlays() {
        XCTAssertEqual(builder.overlays(for: [], selectedRowID: nil), [])
    }

    /// 責務: 行のある種類だけを種類の順(入力の順でなく)に作り、id と題名のキーが種類ごとの値であることを確かめます。
    func testCreatesOverlaysOnlyForKindsWithRowsInKindOrder() {
        let rows = [
            Values.row(id: 0, kind: .slowDown, outcome: .observedOnly),
            Values.row(id: 1, kind: .speedLimit, outcome: .compliant)
        ]

        let overlays = builder.overlays(for: rows, selectedRowID: nil)

        XCTAssertEqual(overlays.map(\.id), ["road_regulation.speed_limit", "road_regulation.slow_down"])
        XCTAssertEqual(overlays.map(\.titleKey), ["analysis.road_regulation.overlay.speed_limit", "analysis.road_regulation.overlay.slow_down"])
    }

    /// 責務: 4種類すべてに行があれば4つ作ることを確かめます。
    func testCreatesFourOverlaysWhenEveryKindHasRows() {
        let rows = [
            Values.row(id: 0, kind: .oneWay, outcome: .compliant),
            Values.row(id: 1, kind: .stop, outcome: .compliant),
            Values.row(id: 2, kind: .slowDown, outcome: .observedOnly),
            Values.row(id: 3, kind: .speedLimit, outcome: .compliant)
        ]

        let ids = builder.overlays(for: rows, selectedRowID: nil).map(\.id)

        XCTAssertEqual(ids, ["road_regulation.speed_limit", "road_regulation.stop", "road_regulation.one_way", "road_regulation.slow_down"])
    }

    /// 責務: run を結果の優先(possibleIssue が先)→ 同じ結果は id の昇順に並べ、連番の範囲が行と一致することを確かめます。
    func testRunsFollowOutcomePriorityThenID() throws {
        let overlay = try XCTUnwrap(builder.overlays(for: speedRows(), selectedRowID: nil).first)
        let expected: [ClosedRange<Int64>] = [30...40, 10...20, 70...80, 0...5, 50...60]

        XCTAssertEqual(overlay.runs.map(\.sequenceRange), expected)
        XCTAssertEqual(overlay.runs.map(\.category), [.tone(.caution), .tone(.caution), .tone(.unknown), .tone(.positive), .tone(.neutral)])
    }

    /// 責務: possibleIssue(id 5)と compliant(id 1)では、id が大きくても possibleIssue が先になることを確かめます。
    func testPossibleIssueComesBeforeCompliantRegardlessOfID() throws {
        let rows = [
            Values.row(id: 1, kind: .stop, outcome: .compliant, sequences: 0...1),
            Values.row(id: 5, kind: .stop, outcome: .possibleIssue, sequences: 8...9)
        ]

        let overlay = try XCTUnwrap(builder.overlays(for: rows, selectedRowID: nil).first)

        XCTAssertEqual(overlay.runs.map(\.sequenceRange), [8...9, 0...1])
    }

    /// 責務: run の色の分類は、表引きでなく行の `category` を写すことを確かめます。
    func testRunCategoryComesFromRow() throws {
        let rows = [Values.row(id: 0, kind: .oneWay, outcome: .compliant, sequences: 3...4, category: .ramp(step: 2))]

        let overlay = try XCTUnwrap(builder.overlays(for: rows, selectedRowID: nil).first)

        XCTAssertEqual(overlay.runs, [RouteAnalysisColorRun(sequenceRange: 3...4, category: .ramp(step: 2))])
    }

    /// 責務: 凡例が、現れた結果だけを allCases の順に並べ、最後に `.base` と「該当する規制なし」を足し、id が 0 からの連番であることを確かめます。
    func testLegendListsPresentOutcomesThenBase() throws {
        let overlay = try XCTUnwrap(builder.overlays(for: speedRows(), selectedRowID: nil).first)
        let expected: [RouteAnalysisLegendEntry] = [
            .init(id: 0, category: .tone(.caution), text: "<road_regulation.verdict.speed_limit.exceeded>"),
            .init(id: 1, category: .tone(.unknown), text: "<analysis.road_regulation.outcome.undetermined>"),
            .init(id: 2, category: .tone(.positive), text: "<road_regulation.verdict.speed_limit.within_limit>"),
            .init(id: 3, category: .tone(.neutral), text: "<road_regulation.verdict.speed_limit.unregulated>"),
            .init(id: 4, category: .base, text: "<analysis.road_regulation.legend.not_applicable>")
        ]

        XCTAssertEqual(overlay.legend, expected)
    }

    /// 責務: 結果が1つだけの種類では、凡例がその結果と `.base` の2項目になることを確かめます。
    func testLegendWithSingleOutcome() throws {
        let rows = [
            Values.row(id: 0, kind: .slowDown, outcome: .observedOnly),
            Values.row(id: 1, kind: .slowDown, outcome: .observedOnly)
        ]

        let overlay = try XCTUnwrap(builder.overlays(for: rows, selectedRowID: nil).first)
        let expected: [RouteAnalysisLegendEntry] = [
            .init(id: 0, category: .tone(.neutral), text: "<road_regulation.verdict.slow_down.observed>"),
            .init(id: 1, category: .base, text: "<analysis.road_regulation.legend.not_applicable>")
        ]

        XCTAssertEqual(overlay.legend, expected)
    }

    /// 責務: 凡例が種類ごとに作られ、他の種類の結果が混ざらないことを確かめます。
    func testLegendIsPerKind() throws {
        let rows = [
            Values.row(id: 0, kind: .speedLimit, outcome: .possibleIssue),
            Values.row(id: 1, kind: .stop, outcome: .compliant)
        ]

        let overlays = builder.overlays(for: rows, selectedRowID: nil)
        let stop = try XCTUnwrap(overlays.last)

        XCTAssertEqual(stop.legend.map(\.text), ["<road_regulation.verdict.stop.stopped>", "<analysis.road_regulation.legend.not_applicable>"])
        XCTAssertEqual(stop.runs.count, 1)
    }
}
