import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationSettingsTextKeys` が、状態・段階・エラー・一覧の確認の状態ごとに、A11 の一覧にあるキーを返すことを検証します。
@MainActor
final class RoadRegulationSettingsTextKeysTests: XCTestCase {
    private typealias Row = RoadRegulationPrefectureRowTests
    private let keys = RoadRegulationSettingsTextKeys()

    /// 全段階の値です。
    private static let allPhases: [RoadRegulationImportPhase] = [
        .preparing, .fetchingCatalog,
        .downloading(RoadRegulationTransferProgress(receivedBytes: 1, expectedBytes: 2)),
        .importing(RoadRegulationArchiveReadProgress(processedCompressedBytes: 1, totalCompressedBytes: 2), importedCount: 3),
        .activating, .cleaningUp,
    ]

    /// 全エラーの値です(A11 のエラーのキーと同じ順)。
    private static let allErrors: [RoadRegulationImportError] = [
        .catalogUnavailable, .catalogFormatChanged, .prefectureNotInCatalog, .downloadFailed, .archiveInvalid,
        .csvFormatChanged, .noRegulationsInArchive, .insufficientStorage, .storageUnavailable,
    ]

    /// 未取得の行は「未取得」です。
    ///
    /// 責務: 版も取り込みも失敗も無い行のキーを確認します。
    func testNotDownloadedStatus() {
        XCTAssertEqual(keys.statusKey(for: Row.row()), "road_regulation.status.not_downloaded")
    }

    /// 取得済みで更新の無い行は「取得済み」です。
    ///
    /// 責務: 版だけがある行のキーを確認します。
    func testDownloadedStatus() {
        XCTAssertEqual(keys.statusKey(for: Row.row(dataset: true)), "road_regulation.status.downloaded")
    }

    /// 取得済みで一覧の方が新しい行は「更新あり」です。
    ///
    /// 責務: 更新ありの行のキーを確認します。
    func testUpdateAvailableStatus() {
        XCTAssertEqual(keys.statusKey(for: Row.row(dataset: true, isUpdateAvailable: true)), "road_regulation.status.update_available")
    }

    /// 取り込みに失敗して前の版がある行は「失敗して前の版を使用中」です。
    ///
    /// 責務: 失敗と版がある行のキーを確認します。
    func testFailedKeepsPreviousStatus() {
        XCTAssertEqual(keys.statusKey(for: Row.row(dataset: true, lastFailure: .downloadFailed)), "road_regulation.status.failed_keeps_previous")
    }

    /// 版の無い行は、失敗していても「未取得」です。
    ///
    /// 責務: 版が無い時に失敗より未取得が優先されることを確認します。
    func testNotDownloadedWinsOverFailureWithoutDataset() {
        XCTAssertEqual(keys.statusKey(for: Row.row(lastFailure: .downloadFailed)), "road_regulation.status.not_downloaded")
        XCTAssertEqual(keys.statusKey(for: Row.row(lastFailure: .archiveInvalid, isUpdateAvailable: true)), "road_regulation.status.not_downloaded")
    }

    /// 版があり失敗もある行は、更新ありでも「失敗して前の版を使用中」です。
    ///
    /// 責務: 失敗が更新ありより優先されることを確認します。
    func testFailureWinsOverUpdateAvailable() {
        let row = Row.row(dataset: true, lastFailure: .insufficientStorage, isUpdateAvailable: true)

        XCTAssertEqual(keys.statusKey(for: row), "road_regulation.status.failed_keeps_previous")
    }

    /// 取り込み中の行は、版・失敗・更新の有無にかかわらず、どの段階でも「取り込み中」です。
    ///
    /// 責務: 取り込み中が他の状態より優先されることを、全段階と全組み合わせで確認します。
    func testImportingStatusWinsInEveryCombination() {
        for phase in Self.allPhases {
            for hasDataset in [false, true] {
                let failures: [RoadRegulationImportError?] = [nil, .downloadFailed]
                for failure in failures {
                    let row = Row.row(dataset: hasDataset, activeImport: phase, lastFailure: failure, isUpdateAvailable: hasDataset)
                    XCTAssertEqual(keys.statusKey(for: row), "road_regulation.status.importing", "\(phase) \(hasDataset) \(String(describing: failure))")
                }
            }
        }
    }

    /// 段階ごとのキーは A11 の段階のキーと順に一致します。
    ///
    /// 責務: `phaseKey` の全分岐を確認します。
    func testPhaseKeys() {
        XCTAssertEqual(Self.allPhases.map(keys.phaseKey), RoadRegulationSettingsKeyCatalog.phaseKeys)
    }

    /// エラーごとのキーは `road_regulation.error.<snake_case>` です。
    ///
    /// 責務: `errorKey` の全分岐を確認します。
    func testErrorKeys() {
        XCTAssertEqual(Self.allErrors.map(keys.errorKey), RoadRegulationSettingsKeyCatalog.errorKeys)
    }

    /// 一覧の確認中は「確認中」、確認済みは「確認済み」、失敗はそのエラーのキーです。
    ///
    /// 責務: `catalogStatusKey` の分岐(未確認を除く)を確認します。
    func testCatalogStatusKeys() {
        let catalog = RoadRegulationTestValues.catalog([RoadRegulationTestValues.prefecture(47)])

        XCTAssertEqual(keys.catalogStatusKey(for: .checking), "road_regulation.data.checking")
        XCTAssertEqual(keys.catalogStatusKey(for: .checked(at: RoadRegulationTestValues.fixedNow, catalog: catalog)), "road_regulation.data.checked")
        XCTAssertEqual(keys.catalogStatusKey(for: .failed(.catalogFormatChanged)), "road_regulation.error.catalog_format_changed")
        XCTAssertEqual(keys.catalogStatusKey(for: .failed(.catalogUnavailable)), "road_regulation.error.catalog_unavailable")
    }

    /// どの入力に対しても、返すキーは A11 の一覧に含まれます。
    ///
    /// 責務: 状態・段階・エラー・一覧の確認の状態の全キーが一覧の中にあることを確認します。
    func testEveryReturnedKeyIsInKeyCatalog() {
        let rows = [Row.row(), Row.row(dataset: true), Row.row(dataset: true, isUpdateAvailable: true),
                    Row.row(dataset: true, lastFailure: .archiveInvalid), Row.row(lastFailure: .downloadFailed),
                    Row.row(activeImport: .preparing)]
        let statuses: [RoadRegulationCatalogCheckStatus] = [.notChecked, .checking, .failed(.catalogUnavailable)]
        let returned = rows.map(keys.statusKey) + Self.allPhases.map(keys.phaseKey) + Self.allErrors.map(keys.errorKey)
            + statuses.map(keys.catalogStatusKey)

        let unknown = returned.filter { !RoadRegulationSettingsKeyCatalog.all.contains($0) }
        XCTAssertEqual(unknown, [])
    }
}
