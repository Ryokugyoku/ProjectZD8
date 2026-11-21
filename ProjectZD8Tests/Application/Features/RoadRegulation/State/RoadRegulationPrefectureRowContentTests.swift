import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationPrefectureRowContent` が、行の状態から出すボタン・可否・段階・失敗の文言キーを決めることを検証します。
@MainActor
final class RoadRegulationPrefectureRowContentTests: XCTestCase {
    private typealias Row = RoadRegulationPrefectureRowTests
    private let keys = RoadRegulationSettingsTextKeys()

    /// 責務: 行から内容を作ります。
    private func content(_ row: RoadRegulationPrefectureRow) -> RoadRegulationPrefectureRowContent {
        RoadRegulationPrefectureRowContent(row: row, textKeys: keys)
    }

    /// 責務: ダウンロード中の段階を作ります。
    private func downloading(_ received: Int64, of expected: Int64) -> RoadRegulationImportPhase {
        .downloading(RoadRegulationTransferProgress(receivedBytes: received, expectedBytes: expected))
    }

    /// 行の値(都道府県・識別子・名前のキー・版)が、そのまま写ります。
    ///
    /// 責務: 素通しの項目を未取得・取得済みで確認します。
    func testPassThroughValues() {
        let empty = content(Row.row(13))
        let withDataset = Row.row(1, dataset: true)
        let filled = content(withDataset)

        XCTAssertEqual(empty.prefecture, RoadRegulationTestValues.prefecture(13))
        XCTAssertEqual(empty.id, 13)
        XCTAssertEqual(empty.nameKey, "road_regulation.prefecture.13")
        XCTAssertNil(empty.dataset)
        XCTAssertEqual(filled.id, 1)
        XCTAssertEqual(filled.nameKey, "road_regulation.prefecture.01")
        XCTAssertEqual(filled.dataset, withDataset.dataset)
    }

    /// 未取得で取り込み中でない行は、取得を出し、削除と中止は出さず、段階も失敗も無い。
    ///
    /// 責務: 未取得の行を確認します。
    func testNotDownloadedRow() {
        let result = content(Row.row())

        XCTAssertTrue(result.showsDownload)
        XCTAssertFalse(result.showsRemove)
        XCTAssertFalse(result.showsCancel)
        XCTAssertNil(result.phaseKey)
        XCTAssertNil(result.progressFraction)
        XCTAssertNil(result.failureKey)
        XCTAssertEqual(result.statusKey, "road_regulation.status.not_downloaded")
        XCTAssertEqual(result.downloadButtonKey, "road_regulation.data.download")
    }

    /// 取得済みの行は、取得(更新)と削除を出し、中止は出さない。更新ありで状態の文言が変わる。
    ///
    /// 責務: 取得済み・更新ありの行を確認します。
    func testDownloadedAndUpdateAvailableRows() {
        let downloaded = content(Row.row(dataset: true))
        let update = content(Row.row(dataset: true, isUpdateAvailable: true))

        XCTAssertTrue(downloaded.showsDownload)
        XCTAssertTrue(downloaded.showsRemove)
        XCTAssertFalse(downloaded.showsCancel)
        XCTAssertEqual(downloaded.statusKey, "road_regulation.status.downloaded")
        XCTAssertEqual(downloaded.downloadButtonKey, "road_regulation.data.update")
        XCTAssertEqual(update.statusKey, "road_regulation.status.update_available")
        XCTAssertEqual(update.downloadButtonKey, "road_regulation.data.update")
        XCTAssertNotEqual(downloaded.statusKey, update.statusKey)
    }

    /// 取り込み中の行は、取得も削除も出さず、中止と段階を出し、版があっても失敗は出さない。
    ///
    /// 責務: 取り込み中の行を、版の有無と失敗の有無の組み合わせで確認します。
    func testImportingRowHidesDownloadAndRemoveAndFailure() {
        for hasDataset in [false, true] {
            let failures: [RoadRegulationImportError?] = [nil, .downloadFailed]
            for failure in failures {
                let row = Row.row(dataset: hasDataset, activeImport: .activating, lastFailure: failure)
                let result = content(row)

                XCTAssertFalse(result.showsDownload, "\(hasDataset) \(String(describing: failure))")
                XCTAssertFalse(result.showsRemove, "\(hasDataset) \(String(describing: failure))")
                XCTAssertTrue(result.showsCancel, "\(hasDataset) \(String(describing: failure))")
                XCTAssertEqual(result.phaseKey, "road_regulation.phase.activating")
                XCTAssertNil(result.failureKey, "\(hasDataset) \(String(describing: failure))")
                XCTAssertEqual(result.statusKey, "road_regulation.status.importing")
            }
        }
    }

    /// 段階の文言キーは、段階ごとに `RoadRegulationSettingsTextKeys` の選択と同じです。
    ///
    /// 責務: 全段階で `phaseKey` が空でなく選択器と一致することを確認します。
    func testPhaseKeyForEveryPhase() {
        let phases: [RoadRegulationImportPhase] = [.preparing, .fetchingCatalog, downloading(1, of: 2), .activating, .cleaningUp]
        for phase in phases {
            let key = content(Row.row(activeImport: phase)).phaseKey ?? ""

            XCTAssertTrue(key.hasPrefix("road_regulation.phase."), "\(phase): \(key)")
            XCTAssertEqual(key, keys.phaseKey(for: phase))
        }
    }

    /// 進み具合は行の値のままです(取り込み中でなければ nil、取り込み中は行の値)。
    ///
    /// 責務: `progressFraction` の素通しを確認します。
    func testProgressFractionPassesThrough() throws {
        let importingRow = Row.row(activeImport: downloading(500, of: 1_000))

        XCTAssertNil(content(Row.row(dataset: true)).progressFraction)
        XCTAssertEqual(try XCTUnwrap(content(importingRow).progressFraction), 0.2, accuracy: 1e-9)
        XCTAssertEqual(content(importingRow).progressFraction, importingRow.progressFraction)
    }

    /// 取り込み中でない行の失敗は、全エラーでそのエラーの文言キーになる。版があれば状態は「失敗して前の版を使用中」。
    ///
    /// 責務: `failureKey` を全エラーで確認します。
    func testFailureKeyForEveryError() {
        let errors: [RoadRegulationImportError] = [
            .catalogUnavailable, .catalogFormatChanged, .prefectureNotInCatalog, .downloadFailed, .archiveInvalid,
            .csvFormatChanged, .noRegulationsInArchive, .insufficientStorage, .storageUnavailable,
        ]
        for error in errors {
            let key = content(Row.row(lastFailure: error)).failureKey ?? ""

            XCTAssertTrue(key.hasPrefix("road_regulation.error."), "\(error): \(key)")
            XCTAssertEqual(key, keys.errorKey(for: error))
        }
        let kept = content(Row.row(dataset: true, lastFailure: .downloadFailed))
        XCTAssertEqual(kept.statusKey, "road_regulation.status.failed_keeps_previous")
        XCTAssertEqual(kept.failureKey, "road_regulation.error.download_failed")
        XCTAssertTrue(kept.showsRemove)
    }

    /// 失敗が無い行は failureKey が nil です。
    ///
    /// 責務: 失敗なしの境界を確認します。
    func testNoFailureGivesNilKey() {
        XCTAssertNil(content(Row.row(dataset: true, isUpdateAvailable: true)).failureKey)
    }

    /// 押せるかは行の同名の値と一致します(他県が取り込み中・版の有無・取り込み中の組み合わせ)。
    ///
    /// 責務: `canStartDownload` と `canRemove` の素通しを確認します。
    func testEnabledFlagsMatchRow() {
        let rows = [
            Row.row(), Row.row(dataset: true), Row.row(isBlockedByOtherImport: true),
            Row.row(dataset: true, isBlockedByOtherImport: true), Row.row(activeImport: .preparing),
            Row.row(dataset: true, activeImport: .cleaningUp),
        ]
        for row in rows {
            let result = content(row)

            XCTAssertEqual(result.canStartDownload, row.canStartDownload)
            XCTAssertEqual(result.canRemove, row.canRemove)
        }
        XCTAssertTrue(content(Row.row(dataset: true)).canRemove)
        XCTAssertFalse(content(Row.row(dataset: true, isBlockedByOtherImport: true)).canRemove)
        XCTAssertTrue(content(Row.row(dataset: true, isBlockedByOtherImport: true)).showsRemove)
    }

    /// 状態と取得ボタンの文言キーは空でなく、既定の選択器でも同じです。
    ///
    /// 責務: 文言キーが空にならないことと `textKeys` の既定値を確認します。
    func testKeysAreNotEmptyAndDefaultMatches() {
        let row = Row.row(dataset: true, isUpdateAvailable: true)
        let result = content(row)

        XCTAssertFalse(result.statusKey.isEmpty)
        XCTAssertFalse(result.downloadButtonKey.isEmpty)
        XCTAssertEqual(RoadRegulationPrefectureRowContent(row: row), result)
    }
}
