import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationSettingsModel` の取り込み(取得の開始・同時に1県だけ・中止・失敗後に前の版が残ること・エラーの表示)を検証します。
@MainActor
final class RoadRegulationSettingsModelImportTests: XCTestCase {
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

    /// 取得が成功すると、行に有効化した版が入り、取り込み中・失敗の表示が消えます。
    ///
    /// 責務: `downloadRequested` から取り込みのユースケースの完了までを確認します。
    func testSuccessfulDownloadStoresDataset() async throws {
        guard await harness.makeAppearedModel() else { return }

        harness.model.send(.downloadRequested(Values.prefecture(47)))
        guard await harness.waitUntil("取り込みの完了", { harness.row(47).dataset != nil }) else { return }
        guard await harness.waitUntilIdle() else { return }

        let active = try XCTUnwrap(harness.imports.datasets.currentActiveDatasets.first)
        XCTAssertEqual(harness.row(47).dataset, active)
        XCTAssertNil(harness.row(47).lastFailure)
        XCTAssertNil(harness.model.state.presentedError)
        XCTAssertEqual(harness.imports.source.downloadedEntries.map(\.prefecture), [Values.prefecture(47)])
        XCTAssertEqual(harness.model.state.summary.downloadedCount, 1)
    }

    /// 取り込み中は、その県が取り込み中として示され、まとめも取り込み中です。
    ///
    /// 責務: 取り込み中の状態(県・行の段階・状態の文言キー・まとめ)を確認します。
    func testImportInProgressIsShownOnRowAndSummary() async throws {
        guard await harness.makeAppearedModel() else { return }
        harness.imports.source.downloadGate.close()

        harness.model.send(.downloadRequested(Values.prefecture(47)))
        guard await harness.waitUntilImportIsBlocked(47) else { return }

        XCTAssertEqual(harness.model.state.importingPrefecture, Values.prefecture(47))
        XCTAssertTrue(harness.model.state.summary.isImporting)
        XCTAssertFalse(harness.row(47).canStartDownload)
        XCTAssertTrue(harness.row(13).isBlockedByOtherImport)
        XCTAssertFalse(harness.row(13).canStartDownload)
        XCTAssertFalse(harness.row(47).isBlockedByOtherImport)
        XCTAssertEqual(RoadRegulationSettingsTextKeys().statusKey(for: harness.row(47)), "road_regulation.status.importing")
        harness.imports.source.downloadGate.open()
        _ = await harness.waitUntilIdle()
    }

    /// 取り込み中に別の県の取得を頼んでも始めません(同時に取り込めるのは1県だけ)。
    ///
    /// 責務: 2件目の `downloadRequested` が無視されることを確認します。
    func testOnlyOnePrefectureImportsAtATime() async throws {
        guard await harness.makeAppearedModel() else { return }
        harness.imports.source.downloadGate.close()
        harness.model.send(.downloadRequested(Values.prefecture(47)))
        guard await harness.waitUntilImportIsBlocked(47) else { return }

        harness.model.send(.downloadRequested(Values.prefecture(13)))
        harness.model.send(.downloadRequested(Values.prefecture(47)))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.imports.source.downloadedEntries.count, 1)
        XCTAssertEqual(harness.model.state.importingPrefecture, Values.prefecture(47))
        XCTAssertNil(harness.row(13).activeImport)
        harness.imports.source.downloadGate.open()
        guard await harness.waitUntilIdle() else { return }
        XCTAssertEqual(harness.imports.source.downloadedEntries.map(\.prefecture), [Values.prefecture(47)])
        XCTAssertNil(harness.row(13).dataset)
    }

    /// 取り込み中に中止すると、取り込み前の状態に戻り(前の版のまま・失敗もエラーの表示も無し)、有効化しません。
    ///
    /// 責務: `cancelRequested` で取り込みが取り消され、状態が戻ることを確認します。
    func testCancelRestoresPreviousState() async throws {
        let previous = Values.dataset(Values.prefecture(47))
        harness.seed([previous])
        guard await harness.makeAppearedModel() else { return }
        harness.imports.source.downloadGate.close()
        harness.model.send(.downloadRequested(Values.prefecture(47)))
        guard await harness.waitUntilImportIsBlocked(47) else { return }

        harness.model.send(.cancelRequested)
        guard await harness.waitUntilIdle() else { return }
        harness.imports.source.downloadGate.open()
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.row(47).dataset, previous)
        XCTAssertNil(harness.row(47).lastFailure)
        XCTAssertNil(harness.model.state.presentedError)
        XCTAssertTrue(harness.imports.datasets.activations.isEmpty)
        XCTAssertEqual(harness.imports.datasets.currentActiveDatasets, [previous])
        XCTAssertTrue(harness.row(47).canStartDownload)
    }

    /// 取り込みに失敗しても、前の版の情報は行に残り、失敗の理由が出て、状態は「失敗して前の版を使用中」です。
    ///
    /// 責務: 失敗後の行(版・失敗・状態の文言キー)とエラーの表示を確認します。
    func testFailureKeepsPreviousDatasetAndPresentsError() async throws {
        let previous = Values.dataset(Values.prefecture(47))
        harness.seed([previous])
        harness.imports.source.failDownload(with: .downloadFailed)
        guard await harness.makeAppearedModel() else { return }

        harness.model.send(.downloadRequested(Values.prefecture(47)))
        guard await harness.waitUntil("失敗の表示", { harness.row(47).lastFailure == .downloadFailed }) else { return }
        guard await harness.waitUntilIdle() else { return }

        XCTAssertEqual(harness.row(47).dataset, previous)
        XCTAssertEqual(harness.model.state.presentedError, .downloadFailed)
        XCTAssertEqual(RoadRegulationSettingsTextKeys().statusKey(for: harness.row(47)), "road_regulation.status.failed_keeps_previous")
        XCTAssertTrue(harness.row(47).canRemove)
    }

    /// エラーの表示を閉じると、表示中のエラーが消えます(前の版はそのまま)。
    ///
    /// 責務: `errorDismissed` を確認します。
    func testErrorDismissedClearsPresentedError() async throws {
        let previous = Values.dataset(Values.prefecture(47))
        harness.seed([previous])
        harness.imports.source.failDownload(with: .downloadFailed)
        guard await harness.makeAppearedModel() else { return }
        harness.model.send(.downloadRequested(Values.prefecture(47)))
        guard await harness.waitUntil("エラーの表示", { harness.model.state.presentedError == .downloadFailed }) else { return }

        harness.model.send(.errorDismissed)

        XCTAssertNil(harness.model.state.presentedError)
        XCTAssertEqual(harness.row(47).dataset, previous)
    }

    /// 取り込み中は画面を開き直しても掃除をしません(取り込み中の版を消さないため)。
    ///
    /// 責務: 取り込み中の `appeared` で `purgeInactiveDatasets` を呼ばないことを確認します。
    func testAppearedDuringImportDoesNotPurge() async throws {
        guard await harness.makeAppearedModel() else { return }
        harness.imports.source.downloadGate.close()
        harness.model.send(.downloadRequested(Values.prefecture(47)))
        guard await harness.waitUntilImportIsBlocked(47) else { return }
        let purgesBefore = harness.imports.datasets.purgeCount

        harness.model.send(.appeared)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.imports.datasets.purgeCount, purgesBefore)
        XCTAssertEqual(harness.model.state.importingPrefecture, Values.prefecture(47))
        harness.imports.source.downloadGate.open()
        _ = await harness.waitUntilIdle()
    }

    /// 取り込みを始めると、その行の前回の失敗の表示が消えます。
    ///
    /// 責務: 再取得の開始で `lastFailure` が消えることを確認します。
    func testStartingImportClearsPreviousFailure() async throws {
        harness.seed([Values.dataset(Values.prefecture(47))])
        harness.imports.source.failDownload(with: .downloadFailed)
        guard await harness.makeAppearedModel() else { return }
        harness.model.send(.downloadRequested(Values.prefecture(47)))
        guard await harness.waitUntil("1回目の失敗", { harness.row(47).lastFailure == .downloadFailed }) else { return }
        guard await harness.waitUntilIdle() else { return }
        harness.model.send(.errorDismissed)
        harness.imports.source.failDownload(with: nil)
        harness.imports.source.downloadGate.close()

        harness.model.send(.downloadRequested(Values.prefecture(47)))
        guard await harness.waitUntilImportIsBlocked(47) else { return }

        XCTAssertNil(harness.row(47).lastFailure)
        harness.imports.source.downloadGate.open()
        guard await harness.waitUntilIdle() else { return }
        XCTAssertNil(harness.row(47).lastFailure)
    }
}
