import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationSettingsState` の初期状態(47行)と、まとめ(件数・最も古い基準月・最新の取得日・取り込み中・文言キー)を検証します。
@MainActor
final class RoadRegulationSettingsStateTests: XCTestCase {
    private typealias Values = RoadRegulationTestValues

    /// 版が無ければ、47行がすべて未取得で、一覧は未確認、取り込み・削除の確認・エラーはありません。
    ///
    /// 責務: 空の初期状態の全項目を確認します。
    func testInitialStateWithoutDatasets() {
        let state = RoadRegulationSettingsState.initial(datasets: [])

        XCTAssertEqual(state.rows.map(\.prefecture), JapanesePrefectureCode.all)
        XCTAssertTrue(state.rows.allSatisfy { $0.dataset == nil && $0.activeImport == nil && $0.lastFailure == nil && !$0.isUpdateAvailable })
        XCTAssertEqual(state.catalogStatus, .notChecked)
        XCTAssertNil(state.importingPrefecture)
        XCTAssertNil(state.pendingRemoval)
        XCTAssertNil(state.presentedError)
    }

    /// 版は県ごとの行に入り、行は並べ替えずに1〜47の順のままです(渡した版の順に依存しない)。
    ///
    /// 責務: 版の割り当てを確認します。
    func testInitialStatePlacesDatasetsOnTheirRows() {
        let tokyo = Values.dataset(Values.prefecture(13))
        let okinawa = Values.dataset(Values.prefecture(47))
        let hokkaido = Values.dataset(Values.prefecture(1))

        let state = RoadRegulationSettingsState.initial(datasets: [okinawa, hokkaido, tokyo])

        XCTAssertEqual(state.rows.count, 47)
        XCTAssertEqual(state.rows.map(\.prefecture), JapanesePrefectureCode.all)
        XCTAssertEqual(state.rows[0].dataset, hokkaido)
        XCTAssertEqual(state.rows[12].dataset, tokyo)
        XCTAssertEqual(state.rows[46].dataset, okinawa)
        XCTAssertEqual(state.rows.filter { $0.dataset != nil }.count, 3)
        XCTAssertTrue(state.rows.allSatisfy { !$0.isUpdateAvailable && $0.activeImport == nil })
    }

    /// 版が無い時のまとめは0件で、基準月と取得日は無く、文言は「未取得」です。
    ///
    /// 責務: 0件のまとめを確認します。
    func testSummaryWithoutDatasets() {
        let summary = RoadRegulationSettingsState.initial(datasets: []).summary

        XCTAssertEqual(summary.downloadedCount, 0)
        XCTAssertNil(summary.oldestDataMonth)
        XCTAssertNil(summary.latestDownloadedAt)
        XCTAssertFalse(summary.isImporting)
        XCTAssertEqual(summary.summaryKey, "road_regulation.settings.summary.none")
    }

    /// 版がある時のまとめは、件数・最も古い基準月・最新の取得日で、文言は「N 件」です。
    ///
    /// 責務: 複数の版からの最小の基準月と最大の取得日を確認します。
    func testSummaryWithDatasets() {
        let newer = Values.dataset(Values.prefecture(13), month: Values.month(2026, 9), downloadedAt: Values.fixedNow)
        let older = Values.dataset(Values.prefecture(47), month: Values.month(2025, 12), downloadedAt: Values.fixedNow.addingTimeInterval(-3_600))
        let middle = Values.dataset(Values.prefecture(27), month: Values.month(2026, 3), downloadedAt: Values.fixedNow.addingTimeInterval(-60))

        let summary = RoadRegulationSettingsState.initial(datasets: [newer, older, middle]).summary

        XCTAssertEqual(summary.downloadedCount, 3)
        XCTAssertEqual(summary.oldestDataMonth, Values.month(2025, 12))
        XCTAssertEqual(summary.latestDownloadedAt, Values.fixedNow)
        XCTAssertFalse(summary.isImporting)
        XCTAssertEqual(summary.summaryKey, "road_regulation.settings.summary.count")
    }

    /// 取り込み中の県があれば、まとめは取り込み中です。
    ///
    /// 責務: `isImporting` が `importingPrefecture` に従うことを確認します。
    func testSummaryReflectsImportingPrefecture() {
        var state = RoadRegulationSettingsState.initial(datasets: [])
        state.importingPrefecture = Values.prefecture(47)

        XCTAssertTrue(state.summary.isImporting)
        XCTAssertEqual(state.summary.downloadedCount, 0)
    }

    /// まとめの文言キーは、件数が0なら「未取得」、1以上なら「N 件」です(件数1の境界)。
    ///
    /// 責務: `summaryKey` の分岐を、件数の境界で確認します。
    func testSummaryKeyBoundary() {
        let none = RoadRegulationSettingsSummary(downloadedCount: 0, oldestDataMonth: nil, latestDownloadedAt: nil, isImporting: true)
        let one = RoadRegulationSettingsSummary(
            downloadedCount: 1, oldestDataMonth: Values.month(2026, 9), latestDownloadedAt: Values.fixedNow, isImporting: false
        )

        XCTAssertEqual(none.summaryKey, "road_regulation.settings.summary.none")
        XCTAssertEqual(one.summaryKey, "road_regulation.settings.summary.count")
        XCTAssertTrue(RoadRegulationSettingsKeyCatalog.all.isSuperset(of: [none.summaryKey, one.summaryKey]))
    }
}
