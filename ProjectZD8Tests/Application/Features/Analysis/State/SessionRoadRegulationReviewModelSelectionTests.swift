import Foundation
import XCTest
@testable import ProjectZD8

/// 交通規制の照合のモデルの、行の選択と絞り込みの切り替えを検証します(設計書 §3.4「Overlays」「Sections」・§6.2・§7 TC3)。
///
/// 標準の照合結果の行: 0 指定なし(最高速度)/ 1 超過(最高速度)/ 2 停止(一時停止)/ 3 判定できない(一方通行)。
/// 強調は行の時刻の範囲を前後 0.5 秒広げた範囲です。
@MainActor
final class SessionRoadRegulationReviewModelSelectionTests: XCTestCase {
    private typealias Values = SessionRoadRegulationReviewModelTestValues

    /// モデルと部品の組です。
    private var harness = SessionRoadRegulationReviewModelHarness()

    /// 責務: 止めた呼び出しを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.openAllGates()
        try await super.tearDown()
    }

    /// 責務: 一覧の行の id を種類の順に並べて返します。
    private var sectionRowIDs: [[Int]] {
        harness.state.sections.map { $0.rows.map(\.id) }
    }

    /// 責務: 見えている行を選ぶと選択され、その種類の重ね合わせの強調がその行の範囲1つになり、他の種類は変わらないことを確かめます。
    func testSelectingVisibleRowHighlightsOnlyThatRow() async {
        await harness.load()

        harness.send(.rowSelected(3))

        XCTAssertEqual(harness.state.selectedRowID, 3)
        XCTAssertEqual(harness.state.overlays, Values.standardOverlays(oneWayHighlights: [59.5...70.5]))
    }

    /// 責務: 同じ行をもう一度選ぶと解除され、重ね合わせの強調が選択なしに戻ることを確かめます。
    func testSelectingSameRowAgainDeselects() async {
        await harness.load()
        harness.send(.rowSelected(3))

        harness.send(.rowSelected(3))

        XCTAssertNil(harness.state.selectedRowID)
        XCTAssertEqual(harness.state.overlays, Values.standardOverlays())
    }

    /// 責務: 別の行を選ぶと選択が移ることを確かめます。
    func testSelectingAnotherRowMovesSelection() async {
        await harness.load()
        harness.send(.rowSelected(3))

        harness.send(.rowSelected(1))

        XCTAssertEqual(harness.state.selectedRowID, 1)
        XCTAssertEqual(harness.state.overlays, Values.standardOverlays(speedLimitHighlights: [9.5...40.5]))
    }

    /// 責務: 絞り込みで見えない行と、存在しない id は無視されることを確かめます。
    func testHiddenAndUnknownRowsAreIgnored() async {
        await harness.load()
        let before = harness.state

        harness.send(.rowSelected(0))
        harness.send(.rowSelected(2))
        harness.send(.rowSelected(99))

        XCTAssertEqual(harness.state, before)
    }

    /// 責務: loaded でない時(初期・評価中・failed)の選択は無視されることを確かめます。
    func testSelectionIsIgnoredUnlessLoaded() async {
        harness.send(.rowSelected(0))
        XCTAssertNil(harness.state.selectedRowID)
        let gate = harness.enqueue(.success(.reviewed(Values.standardReview())), held: true)
        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForWaiting(on: gate)

        harness.send(.rowSelected(1))

        XCTAssertNil(harness.state.selectedRowID)
        XCTAssertEqual(harness.state.status, .evaluating)
    }

    /// 責務: 「すべて」に切り替えると全行が種類ごとに id の昇順で並び、指定なしの行も選べるようになることを確かめます。
    func testFilterAllShowsAllRowsAndAllowsSelectingThem() async {
        await harness.load()

        harness.send(.filterChanged(.all))
        harness.send(.rowSelected(0))

        XCTAssertEqual(harness.state.filter, .all)
        XCTAssertEqual(sectionRowIDs, [[0, 1], [2], [3], []])
        XCTAssertEqual(harness.state.sections.map(\.emptyMessageKey), [nil, nil, nil, "analysis.road_regulation.list.empty_kind"])
        XCTAssertEqual(harness.state.selectedRowID, 0)
        XCTAssertEqual(harness.state.overlays, Values.standardOverlays(speedLimitHighlights: [-0.5...9.5]))
    }

    /// 責務: 選択中の行が絞り込みで見えなくなると、選択が外れて重ね合わせの強調が選択なしに戻ることを確かめます。
    func testFilterHidingSelectedRowClearsSelection() async {
        await harness.load()
        harness.send(.filterChanged(.all))
        harness.send(.rowSelected(2))

        harness.send(.filterChanged(.attention))

        XCTAssertNil(harness.state.selectedRowID)
        XCTAssertEqual(sectionRowIDs, [[1], [], [3], []])
        XCTAssertEqual(harness.state.overlays, Values.standardOverlays())
    }

    /// 責務: 選択中の行が絞り込みの後も見えていれば、選択と強調が残ることを確かめます。
    func testFilterKeepingSelectedRowKeepsSelection() async {
        await harness.load()
        harness.send(.rowSelected(3))

        harness.send(.filterChanged(.all))

        XCTAssertEqual(harness.state.selectedRowID, 3)
        XCTAssertEqual(sectionRowIDs, [[0, 1], [2], [3], []])
        XCTAssertEqual(harness.state.overlays, Values.standardOverlays(oneWayHighlights: [59.5...70.5]))
    }

    /// 責務: 同じ絞り込みを送っても何も変わらないことを確かめます。
    func testSameFilterDoesNothing() async {
        await harness.load()
        harness.send(.rowSelected(1))
        let before = harness.state

        harness.send(.filterChanged(.attention))

        XCTAssertEqual(harness.state, before)
    }

    /// 責務: loaded でない時も絞り込みの値は変わり、一覧は作られない(空のまま)ことを確かめます。
    func testFilterChangesValueEvenWhenNotLoaded() async {
        harness.sendReadiness(.waitingForRawLog)

        harness.send(.filterChanged(.all))

        XCTAssertEqual(harness.state.filter, .all)
        XCTAssertEqual(harness.state.sections, [])
        XCTAssertEqual(harness.state.status, .waitingForRawLog)
    }

    /// 責務: 評価の開始で選択と内容は空になり、絞り込みは残って、結果の一覧にもその絞り込みが使われることを確かめます。
    func testFilterSurvivesReEvaluation() async {
        await harness.load(raw: .inCloud)
        harness.send(.filterChanged(.all))
        harness.send(.rowSelected(0))
        let gate = harness.enqueue(.success(.reviewed(Values.standardReview())), held: true)

        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForWaiting(on: gate)
        XCTAssertNil(harness.state.selectedRowID)
        XCTAssertEqual(harness.state.sections, [])
        XCTAssertEqual(harness.state.attribution, .empty)
        gate?.open()
        await harness.waitForStatus(.loaded)

        XCTAssertEqual(harness.state.filter, .all)
        XCTAssertEqual(sectionRowIDs, [[0, 1], [2], [3], []])
    }
}
