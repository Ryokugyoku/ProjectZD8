import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationSettingsModel` の表示時の読み込みと掃除、「更新を確認」と更新ありの判定を検証します。
///
/// 取り込みは `RoadRegulationSettingsModelImportTests`、削除は `RoadRegulationSettingsModelRemovalTests` で検証します。
@MainActor
final class RoadRegulationSettingsModelTests: XCTestCase {
    private typealias Values = RoadRegulationTestValues
    private var harness: RoadRegulationSettingsModelHarness!

    override func setUp() async throws {
        try await super.setUp()
        harness = try RoadRegulationSettingsModelHarness()
    }

    override func tearDown() async throws {
        harness.tearDown()
        harness = nil
        try await super.tearDown()
    }

    /// 画面を開くと、手元の版が行に出て、残骸(未完了の版と一時ファイル)を掃除し、通信はしません。
    ///
    /// 責務: `appeared` の読み込み・掃除と、一覧を取りに行かないことを確認します。
    func testAppearedLoadsDatasetsAndPurgesWithoutNetwork() async throws {
        let tokyo = Values.dataset(Values.prefecture(13))
        harness.seed([tokyo])
        harness.imports.datasets.seedInactive(RoadRegulationDatasetID(rawValue: UUID()), prefecture: Values.prefecture(47), state: .importing)

        guard await harness.makeAppearedModel() else { return }
        guard await harness.waitUntil("残骸の掃除", {
            harness.imports.datasets.importingDatasetIDs.isEmpty && harness.imports.source.leftoverRemovalCount >= 1
        }) else { return }
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.row(13).dataset, tokyo)
        XCTAssertEqual(harness.model.state.rows.count, 47)
        XCTAssertEqual(harness.model.state.catalogStatus, .notChecked)
        XCTAssertEqual(harness.imports.source.catalogCallCount, 0, "表示しただけで一覧を取りに行きました")
        XCTAssertTrue(harness.imports.source.downloadedEntries.isEmpty)
        XCTAssertEqual(harness.model.state.summary.downloadedCount, 1)
    }

    /// 「更新を確認」を押すと、確認中になり、終わると確認の時刻と一覧を持った確認済みになります。
    ///
    /// 責務: `checkUpdatesRequested` の状態の移り変わりを確認します。
    func testCheckUpdatesMovesThroughCheckingToChecked() async throws {
        guard await harness.makeAppearedModel() else { return }
        harness.imports.source.catalogGate.close()

        harness.model.send(.checkUpdatesRequested)
        guard await harness.waitUntil("確認中", { harness.model.state.catalogStatus == .checking }) else { return }
        harness.imports.source.catalogGate.open()
        let expected = RoadRegulationCatalogCheckStatus.checked(at: Values.fixedNow, catalog: RoadRegulationSettingsModelHarness.catalog())
        guard await harness.waitUntil("確認済み", { harness.model.state.catalogStatus == expected }) else { return }

        XCTAssertEqual(harness.imports.source.catalogCallCount, 1)
    }

    /// 一覧の公開の印が手元と違い基準月も新しい県は「更新あり」、同じ県は「更新なし」です。
    ///
    /// 責務: 確認の後の `isUpdateAvailable` と状態の文言キーを確認します。
    func testCheckUpdatesMarksNewerPublicationsAsUpdateAvailable() async throws {
        let stale = Values.dataset(Values.prefecture(13), month: Values.month(2026, 8), stamp: "202610010000")
        let current = Values.dataset(Values.prefecture(47), month: Values.month(2026, 9), stamp: Values.publicationStamp)
        harness.seed([stale, current])
        guard await harness.makeAppearedModel() else { return }

        harness.model.send(.checkUpdatesRequested)
        guard await harness.waitUntil("確認済み", {
            if case .checked = harness.model.state.catalogStatus { true } else { false }
        }) else { return }

        XCTAssertTrue(harness.row(13).isUpdateAvailable)
        XCTAssertFalse(harness.row(47).isUpdateAvailable)
        XCTAssertEqual(RoadRegulationSettingsTextKeys().statusKey(for: harness.row(13)), "road_regulation.status.update_available")
        XCTAssertEqual(RoadRegulationSettingsTextKeys().statusKey(for: harness.row(47)), "road_regulation.status.downloaded")
        XCTAssertEqual(harness.row(13).dataset, stale)
    }

    /// 一覧の取得が失敗すると失敗の状態になり、手元の版はそのままで、更新ありにはなりません。
    ///
    /// 責務: 確認の失敗が成功や空の一覧に潰されないことを確認します。
    func testCheckUpdatesFailureKeepsLocalData() async throws {
        let stale = Values.dataset(Values.prefecture(13), stamp: "202610010000")
        harness.seed([stale])
        harness.imports.source.failCatalog(with: .catalogFormatChanged)
        guard await harness.makeAppearedModel() else { return }

        harness.model.send(.checkUpdatesRequested)
        guard await harness.waitUntil("確認の失敗", {
            harness.model.state.catalogStatus == .failed(.catalogFormatChanged)
        }) else { return }

        XCTAssertEqual(harness.row(13).dataset, stale)
        XCTAssertFalse(harness.row(13).isUpdateAvailable)
        XCTAssertNil(harness.model.state.importingPrefecture)
    }

    /// 確認済みの一覧があれば、取得の時はその一覧を使い、一覧を取り直しません。
    ///
    /// 責務: 確認した一覧が取り込みに渡されることを確認します。
    func testDownloadAfterCheckReusesCheckedCatalog() async throws {
        guard await harness.makeAppearedModel() else { return }
        harness.model.send(.checkUpdatesRequested)
        guard await harness.waitUntil("確認済み", {
            if case .checked = harness.model.state.catalogStatus { true } else { false }
        }) else { return }

        harness.model.send(.downloadRequested(Values.prefecture(47)))
        guard await harness.waitUntil("取り込みの完了", { harness.row(47).dataset != nil }) else { return }

        XCTAssertEqual(harness.imports.source.catalogCallCount, 1)
        XCTAssertFalse(harness.row(47).isUpdateAvailable)
    }

    /// 作った直後のモデルは、版が手元にあっても空の47行で、一覧は未確認です(表示されるまで読み込まない)。
    ///
    /// 責務: 初期状態を確認します。
    func testNewModelStartsWithEmptyRows() {
        harness.seed([Values.dataset(Values.prefecture(13))])

        let model = harness.makeModel()

        XCTAssertEqual(model.state.rows.map(\.prefecture), JapanesePrefectureCode.all)
        XCTAssertTrue(model.state.rows.allSatisfy { $0.dataset == nil && $0.activeImport == nil })
        XCTAssertEqual(model.state.catalogStatus, .notChecked)
        XCTAssertEqual(harness.imports.source.catalogCallCount, 0)
    }

    /// 確認中にもう一度「更新を確認」を押しても、一覧を取り直しません。
    ///
    /// 責務: 確認中の `checkUpdatesRequested` が無視されることを確認します。
    func testCheckUpdatesWhileCheckingIsIgnored() async throws {
        guard await harness.makeAppearedModel() else { return }
        harness.imports.source.catalogGate.close()
        harness.model.send(.checkUpdatesRequested)
        guard await harness.waitUntil("確認中", { harness.imports.source.catalogGate.isWaiting }) else { return }

        harness.model.send(.checkUpdatesRequested)
        await LocationRecordingBoundedWaiter.settle()
        harness.imports.source.catalogGate.open()
        guard await harness.waitUntil("確認済み", {
            if case .checked = harness.model.state.catalogStatus { true } else { false }
        }) else { return }
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.imports.source.catalogCallCount, 1)
    }
}
