import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationPrefectureRow` の識別子・名前のキー・進捗の割合(§3.7)・押せるボタンを検証します。
@MainActor
final class RoadRegulationPrefectureRowTests: XCTestCase {
    private typealias Values = RoadRegulationTestValues

    /// 責務: 検証用の行を作ります。
    static func row(
        _ number: Int = 47,
        dataset: Bool = false,
        activeImport: RoadRegulationImportPhase? = nil,
        lastFailure: RoadRegulationImportError? = nil,
        isUpdateAvailable: Bool = false,
        isBlockedByOtherImport: Bool = false
    ) -> RoadRegulationPrefectureRow {
        let prefecture = RoadRegulationTestValues.prefecture(number)
        return RoadRegulationPrefectureRow(
            prefecture: prefecture, dataset: dataset ? RoadRegulationTestValues.dataset(prefecture) : nil,
            activeImport: activeImport, lastFailure: lastFailure, isUpdateAvailable: isUpdateAvailable,
            isBlockedByOtherImport: isBlockedByOtherImport
        )
    }

    /// 責務: ダウンロードの段階を作ります。
    private func downloading(_ received: Int64, of expected: Int64) -> RoadRegulationImportPhase {
        .downloading(RoadRegulationTransferProgress(receivedBytes: received, expectedBytes: expected))
    }

    /// 責務: 取り込みの段階を作ります。
    private func importing(_ processed: Int64, of total: Int64) -> RoadRegulationImportPhase {
        .importing(RoadRegulationArchiveReadProgress(processedCompressedBytes: processed, totalCompressedBytes: total), importedCount: 0)
    }

    /// 識別子は都道府県コードの値で、名前のキーは2桁の番号です(1 → "01"、47 → "47")。
    ///
    /// 責務: `id` と `nameKey` を両端の県で確認します。
    func testIdentifierAndNameKey() {
        XCTAssertEqual(Self.row(1).id, 1)
        XCTAssertEqual(Self.row(1).nameKey, "road_regulation.prefecture.01")
        XCTAssertEqual(Self.row(9).nameKey, "road_regulation.prefecture.09")
        XCTAssertEqual(Self.row(47).id, 47)
        XCTAssertEqual(Self.row(47).nameKey, "road_regulation.prefecture.47")
    }

    /// 47県の名前のキーが、A11 の都道府県のキーの一覧と一致します。
    ///
    /// 責務: 名前のキーの全件を確認します。
    func testAllNameKeysMatchKeyCatalog() {
        let keys = JapanesePrefectureCode.all.map { Self.row($0.rawValue).nameKey }

        XCTAssertEqual(keys, RoadRegulationSettingsKeyCatalog.prefectureKeys)
    }

    /// 取り込み中でなければ、進捗の割合は `nil` です。
    ///
    /// 責務: 進捗の無い行を確認します。
    func testProgressFractionIsNilWithoutImport() {
        XCTAssertNil(Self.row(dataset: true).progressFraction)
        XCTAssertNil(Self.row(lastFailure: .downloadFailed).progressFraction)
    }

    /// ダウンロード中は「受信 / 予定 × 0.4」です(0 → 0、半分 → 0.2、全部 → 0.4)。
    ///
    /// 責務: ダウンロードの段階の割合を3点で確認します。
    func testDownloadingFraction() throws {
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: downloading(0, of: 1_000)).progressFraction), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: downloading(500, of: 1_000)).progressFraction), 0.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: downloading(1_000, of: 1_000)).progressFraction), 0.4, accuracy: 1e-9)
    }

    /// 取り込み中は「0.4 + 処理した圧縮バイト / 全圧縮バイト × 0.55」です(0 → 0.4、半分 → 0.675、全部 → 0.95)。
    ///
    /// 責務: 取り込みの段階の割合を3点で確認します。
    func testImportingFraction() throws {
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: importing(0, of: 2_000)).progressFraction), 0.4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: importing(1_000, of: 2_000)).progressFraction), 0.675, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: importing(2_000, of: 2_000)).progressFraction), 0.95, accuracy: 1e-9)
    }

    /// 有効化は 0.95、掃除は 0.975 です。
    ///
    /// 責務: 最後の2段階の割合を確認します。
    func testActivatingAndCleaningUpFractions() throws {
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: .activating).progressFraction), 0.95, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: .cleaningUp).progressFraction), 0.975, accuracy: 1e-9)
    }

    /// 準備と一覧の取得の割合は 0 です。
    ///
    /// 責務: 最初の2段階の割合を確認します。
    func testPreparingAndFetchingCatalogFractionsAreZero() throws {
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: .preparing).progressFraction), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: .fetchingCatalog).progressFraction), 0, accuracy: 1e-9)
    }

    /// 予定の大きさが分からない(nil)か0以下のダウンロードは、割合が `nil` です。受信が予定を超えても 0.4 を超えません。
    ///
    /// 責務: ダウンロードの割合の境界(予定 nil・0・負・超過)を確認します。
    func testDownloadingFractionEdgeCases() throws {
        let unknown = RoadRegulationImportPhase.downloading(RoadRegulationTransferProgress(receivedBytes: 10, expectedBytes: nil))

        XCTAssertNil(Self.row(activeImport: unknown).progressFraction)
        XCTAssertNil(Self.row(activeImport: downloading(10, of: 0)).progressFraction)
        XCTAssertNil(Self.row(activeImport: downloading(10, of: -1)).progressFraction)
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: downloading(2_000, of: 1_000)).progressFraction), 0.4, accuracy: 1e-9)
    }

    /// 全圧縮バイトが0の取り込みは 0.4、処理が全体を超えても 0.95 を超えません。
    ///
    /// 責務: 取り込みの割合の境界(全体0・超過)を確認します。
    func testImportingFractionEdgeCases() throws {
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: importing(0, of: 0)).progressFraction), 0.4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Self.row(activeImport: importing(300, of: 100)).progressFraction), 0.95, accuracy: 1e-9)
    }

    /// 取り込みの段階の境目で、割合が戻りません(ダウンロードの終わり ≤ 取り込みの始め ≤ 取り込みの終わり ≤ 有効化)。
    ///
    /// 責務: 段階をまたいだ割合の単調性を確認します。
    func testFractionDoesNotGoBackAcrossPhases() throws {
        let phases = [downloading(1_000, of: 1_000), importing(0, of: 10), importing(10, of: 10), .activating, .cleaningUp]
        let fractions = try phases.map { try XCTUnwrap(Self.row(activeImport: $0).progressFraction) }
        let expected = [0.4, 0.4, 0.95, 0.95, 0.975]

        for (earlier, later) in zip(fractions, fractions.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later, earlier, "割合が戻りました: \(fractions)")
        }
        XCTAssertEqual(fractions.count, expected.count)
        for (actual, value) in zip(fractions, expected) {
            XCTAssertEqual(actual, value, accuracy: 1e-9, "各段階の代表の値: \(fractions)")
        }
    }

    /// この行も他の県も取り込み中でなければ取得を始められ、どちらかが取り込み中なら始められません。
    ///
    /// 責務: `canStartDownload` の分岐を確認します。
    func testCanStartDownload() {
        XCTAssertTrue(Self.row().canStartDownload)
        XCTAssertTrue(Self.row(dataset: true, isUpdateAvailable: true).canStartDownload)
        XCTAssertTrue(Self.row(dataset: true, lastFailure: .downloadFailed).canStartDownload)
        XCTAssertFalse(Self.row(activeImport: .preparing).canStartDownload)
        XCTAssertFalse(Self.row(dataset: true, activeImport: importing(1, of: 2)).canStartDownload)
        XCTAssertFalse(Self.row(isBlockedByOtherImport: true).canStartDownload)
        XCTAssertFalse(Self.row(dataset: true, isUpdateAvailable: true, isBlockedByOtherImport: true).canStartDownload)
    }

    /// 削除できるのは取得済みで、取得を始められる(この行も他県も取り込み中でない)行だけです。
    ///
    /// 責務: `canRemove` の分岐を確認します。
    func testCanRemove() {
        XCTAssertTrue(Self.row(dataset: true).canRemove)
        XCTAssertTrue(Self.row(dataset: true, lastFailure: .archiveInvalid).canRemove)
        XCTAssertFalse(Self.row().canRemove)
        XCTAssertFalse(Self.row(lastFailure: .downloadFailed).canRemove)
        XCTAssertFalse(Self.row(dataset: true, activeImport: .activating).canRemove)
        XCTAssertFalse(Self.row(dataset: true, isBlockedByOtherImport: true).canRemove)
    }
}
