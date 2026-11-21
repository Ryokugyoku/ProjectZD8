import Foundation
import XCTest
@testable import ProjectZD8

/// 交通規制(`road_regulation.*`)の文言キーが、すべて `Localizable.xcstrings` にあり ja / en / es で訳されていることを検証します。
@MainActor
final class RoadRegulationLocalizationTests: XCTestCase {
    private typealias Row = RoadRegulationPrefectureRowTests
    private let textKeys = RoadRegulationSettingsTextKeys()

    /// 責務: 取り込みのエラーを全 case 並べ、case が増えたらコンパイルエラーにします(`switch` に `default` を置かない)。
    private func allErrors() -> [RoadRegulationImportError] {
        let errors: [RoadRegulationImportError] = [
            .catalogUnavailable, .catalogFormatChanged, .prefectureNotInCatalog, .downloadFailed, .archiveInvalid,
            .csvFormatChanged, .noRegulationsInArchive, .insufficientStorage, .storageUnavailable
        ]
        for error in errors {
            switch error {
            case .catalogUnavailable, .catalogFormatChanged, .prefectureNotInCatalog, .downloadFailed, .archiveInvalid,
                 .csvFormatChanged, .noRegulationsInArchive, .insufficientStorage, .storageUnavailable: break
            }
        }
        return errors
    }

    /// 責務: 取り込みの段階を全 case 並べ、case が増えたらコンパイルエラーにします(`switch` に `default` を置かない)。
    private func allPhases() -> [RoadRegulationImportPhase] {
        let phases: [RoadRegulationImportPhase] = [
            .preparing, .fetchingCatalog,
            .downloading(RoadRegulationTransferProgress(receivedBytes: 1, expectedBytes: 2)),
            .importing(RoadRegulationArchiveReadProgress(processedCompressedBytes: 1, totalCompressedBytes: 2), importedCount: 3),
            .activating, .cleaningUp
        ]
        for phase in phases {
            switch phase {
            case .preparing, .fetchingCatalog, .downloading, .importing, .activating, .cleaningUp: break
            }
        }
        return phases
    }

    /// 責務: 行の状態ごと(未取得・取得済み・更新あり・失敗して前の版を使用中・取り込み中)の状態とボタンのキーを作ります。
    private func rowKeys() -> [String] {
        let rows = [
            Row.row(), Row.row(dataset: true), Row.row(dataset: true, isUpdateAvailable: true),
            Row.row(dataset: true, lastFailure: .downloadFailed), Row.row(activeImport: .activating)
        ]
        return rows.map(textKeys.statusKey) + rows.map(textKeys.downloadButtonKey)
    }

    /// 責務: 一覧の確認の状態(未確認・確認中・確認済み・全エラーの失敗)の文言キーを作ります。
    private func catalogStatusKeys() -> [String] {
        let catalog = RoadRegulationTestValues.catalog([RoadRegulationTestValues.prefecture(47)])
        let checked = RoadRegulationCatalogCheckStatus.checked(at: RoadRegulationTestValues.fixedNow, catalog: catalog)
        let simple: [RoadRegulationCatalogCheckStatus] = [.notChecked, .checking, checked]
        return simple.map(textKeys.catalogStatusKey) + allErrors().map { textKeys.catalogStatusKey(for: .failed($0)) }
    }

    /// 責務: まとめ・出典の文言キーを作ります。
    private func summaryAndAttributionKeys() -> [String] {
        let summaries = [0, 1].map {
            RoadRegulationSettingsSummary(downloadedCount: $0, oldestDataMonth: nil, latestDownloadedAt: nil, isImporting: false).summaryKey
        }
        let attribution = [
            RoadRegulationAttribution.sourceKey, RoadRegulationAttribution.usedOnKey,
            RoadRegulationAttribution.processedKey, RoadRegulationAttribution.disclaimerKey
        ]
        return summaries + attribution
    }

    /// 責務: 都道府県名のキーを、47都道府県の行から作ります。
    private func prefectureKeys() -> [String] {
        JapanesePrefectureCode.all.map { code in
            let row = RoadRegulationPrefectureRow(prefecture: code, dataset: nil, activeImport: nil, lastFailure: nil, isUpdateAvailable: false)
            return row.nameKey
        }
    }

    /// 取り込みのエラー9種の文言キーが、カタログにあります。
    ///
    /// 責務: `RoadRegulationImportError` の全 case の `errorKey` を確認します。
    func testErrorKeysAreTranslated() throws {
        let keys = allErrors().map(textKeys.errorKey)
        let catalog = try LocalizableCatalogChecker()
        catalog.assertDistinct(keys, expectedCount: 9)
        catalog.assertAll(keys)
    }

    /// 取り込みの段階6種の文言キーが、カタログにあります。
    ///
    /// 責務: 全段階の `phaseKey` を確認します。
    func testPhaseKeysAreTranslated() throws {
        let keys = allPhases().map(textKeys.phaseKey)
        let catalog = try LocalizableCatalogChecker()
        catalog.assertDistinct(keys, expectedCount: 6)
        catalog.assertAll(keys)
    }

    /// 行の状態とボタンの文言キーが、カタログにあります。
    ///
    /// 責務: 全状態の `statusKey` と `downloadButtonKey` を確認します。
    func testRowStatusAndButtonKeysAreTranslated() throws {
        let keys = Array(Set(rowKeys())).sorted()
        XCTAssertEqual(keys.count, 7, "状態5種とボタン2種(取得・更新)")
        try LocalizableCatalogChecker().assertAll(keys)
    }

    /// 一覧の確認の状態の文言キーが、カタログにあります。
    ///
    /// 責務: 未確認・確認中・確認済み・全エラーの失敗の `catalogStatusKey` を確認します。
    func testCatalogStatusKeysAreTranslated() throws {
        try LocalizableCatalogChecker().assertAll(Array(Set(catalogStatusKeys())).sorted())
    }

    /// まとめと出典の文言キーが、カタログにあります。
    ///
    /// 責務: まとめ2種と出典4種を確認します。
    func testSummaryAndAttributionKeysAreTranslated() throws {
        let keys = summaryAndAttributionKeys()
        let catalog = try LocalizableCatalogChecker()
        catalog.assertDistinct(keys, expectedCount: 6)
        catalog.assertAll(keys)
    }

    /// 都道府県のキーは `01` から `47` の47個で、すべて訳があります。
    ///
    /// 責務: 製品の行が返す名前のキーと、カタログの `road_regulation.prefecture.` のキーが一致することを確認します。
    func testPrefectureKeysAreTranslatedAndExactlyFortySeven() throws {
        let keys = prefectureKeys()
        let catalog = try LocalizableCatalogChecker()
        catalog.assertDistinct(keys, expectedCount: 47)
        XCTAssertEqual(keys, (1...47).map { String(format: "road_regulation.prefecture.%02d", $0) })
        XCTAssertEqual(catalog.catalogKeys(prefix: "road_regulation.prefecture."), keys)
        catalog.assertAll(keys)
    }

    /// 設計書 §6 の A11 の注のキーが、すべてカタログにあります。
    ///
    /// 責務: 期待値の一覧 `RoadRegulationSettingsKeyCatalog.all`(設定・取得・状態・段階・詳細・エラー・出典・都道府県)を確認します。
    func testDesignNoteKeysAreTranslated() throws {
        let keys = RoadRegulationSettingsKeyCatalog.all.sorted()
        XCTAssertEqual(keys.count, 6 + 11 + 5 + 6 + 4 + 9 + 4 + 47)
        try LocalizableCatalogChecker().assertAll(keys)
    }

    /// 判定の「判定できない理由」15種の文言キーが、カタログにあります。
    ///
    /// 責務: 設計書の規則 `road_regulation.undetermined.<snake_case>` で、`RoadRegulationUndeterminedReason.allCases` のキーを確認します。
    func testUndeterminedReasonKeysAreTranslated() throws {
        let keys = RoadRegulationUndeterminedReason.allCases.map { "road_regulation.undetermined." + Self.snakeCase($0.rawValue) }
        let catalog = try LocalizableCatalogChecker()
        catalog.assertDistinct(keys, expectedCount: 15)
        catalog.assertAll(keys)
    }

    /// カタログの `road_regulation.` のキーが、すべて訳されています。
    ///
    /// 責務: 製品コードがまだ使わないキー(判定の文言など)も含め、カタログ側から数えて確認します。
    func testEveryCatalogRoadRegulationKeyIsTranslated() throws {
        let catalog = try LocalizableCatalogChecker()
        let keys = catalog.catalogKeys(prefix: "road_regulation.")
        XCTAssertFalse(keys.isEmpty, "road_regulation.* のキーがカタログに無い")
        catalog.assertAll(keys)
    }

    /// 製品コードが返すキーを、カタログの `road_regulation.` のキーが覆っています。
    ///
    /// 責務: 行・一覧の確認・まとめ・出典・都道府県のキーがすべてカタログの一覧に含まれることを確認します。
    func testCatalogCoversEveryProducedKey() throws {
        let catalog = Set(try LocalizableCatalogChecker().catalogKeys(prefix: "road_regulation."))
        let produced = rowKeys() + catalogStatusKeys() + summaryAndAttributionKeys() + prefectureKeys() + allPhases().map(textKeys.phaseKey)
        XCTAssertTrue(Set(produced).isSubset(of: catalog), "カタログに無い: \(Set(produced).subtracting(catalog).sorted())")
    }

    /// 責務: 小文字始まりのキャメルケースを snake_case にします(`coarseGeometry` → `coarse_geometry`)。
    private static func snakeCase(_ camel: String) -> String {
        var result = ""
        for character in camel {
            if character.isUppercase { result += "_" }
            result += character.lowercased()
        }
        return result
    }
}
