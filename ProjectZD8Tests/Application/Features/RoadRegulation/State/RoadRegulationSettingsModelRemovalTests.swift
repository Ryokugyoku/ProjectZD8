import Foundation
import XCTest
@testable import ProjectZD8

/// `RoadRegulationSettingsModel` の削除(確認してから実行・取り消し・取得済みだけ・取り込み中は削除できない)を検証します。
@MainActor
final class RoadRegulationSettingsModelRemovalTests: XCTestCase {
    private typealias Values = RoadRegulationTestValues
    private var harness: RoadRegulationSettingsModelHarness!
    private var okinawa: RoadRegulationDataset!
    private var tokyo: RoadRegulationDataset!

    override func setUp() async throws {
        try await super.setUp()
        harness = try RoadRegulationSettingsModelHarness()
        okinawa = Values.dataset(Values.prefecture(47))
        tokyo = Values.dataset(Values.prefecture(13))
        harness.seed([okinawa, tokyo])
    }

    override func tearDown() async throws {
        harness.tearDown()
        harness = nil
        okinawa = nil
        tokyo = nil
        try await super.tearDown()
    }

    /// 削除を頼むと確認待ちになるだけで、確認するまで削除しません。
    ///
    /// 責務: `removeRequested` が確認待ちの県を設定し、Repository に触れないことを確認します。
    func testRemoveRequestedOnlyAsksForConfirmation() async throws {
        guard await harness.makeAppearedModel() else { return }

        harness.model.send(.removeRequested(Values.prefecture(47)))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.model.state.pendingRemoval, Values.prefecture(47))
        XCTAssertTrue(harness.imports.datasets.retiredPrefectures.isEmpty)
        XCTAssertEqual(harness.row(47).dataset, okinawa)
    }

    /// 確認すると、その県の版を削除し、行は未取得に戻り、確認待ちは消えます。他の県はそのままです。
    ///
    /// 責務: `removeConfirmed` の実行と、削除後の行を確認します。
    func testRemoveConfirmedDeletesDataset() async throws {
        guard await harness.makeAppearedModel() else { return }
        harness.model.send(.removeRequested(Values.prefecture(47)))

        harness.model.send(.removeConfirmed)
        guard await harness.waitUntil("削除の反映", { harness.row(47).dataset == nil }) else { return }

        XCTAssertEqual(harness.imports.datasets.retiredPrefectures, [Values.prefecture(47)])
        XCTAssertNil(harness.model.state.pendingRemoval)
        XCTAssertEqual(harness.row(13).dataset, tokyo)
        XCTAssertEqual(harness.imports.datasets.currentActiveDatasets, [tokyo])
        XCTAssertEqual(RoadRegulationSettingsTextKeys().statusKey(for: harness.row(47)), "road_regulation.status.not_downloaded")
    }

    /// 確認を取り消すと、確認待ちが消え、何も削除しません。
    ///
    /// 責務: `removeCancelled` を確認します。
    func testRemoveCancelledKeepsDataset() async throws {
        guard await harness.makeAppearedModel() else { return }
        harness.model.send(.removeRequested(Values.prefecture(47)))

        harness.model.send(.removeCancelled)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertNil(harness.model.state.pendingRemoval)
        XCTAssertTrue(harness.imports.datasets.retiredPrefectures.isEmpty)
        XCTAssertEqual(harness.row(47).dataset, okinawa)
    }

    /// 確認待ちが無い時の確認は、何も削除しません。
    ///
    /// 責務: 確認待ちの無い `removeConfirmed` を確認します。
    func testRemoveConfirmedWithoutPendingDoesNothing() async throws {
        guard await harness.makeAppearedModel() else { return }

        harness.model.send(.removeConfirmed)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertTrue(harness.imports.datasets.retiredPrefectures.isEmpty)
        XCTAssertEqual(harness.imports.datasets.currentActiveDatasets, [tokyo, okinawa])
    }

    /// 未取得の県は削除の確認に進みません(削除は取得済みだけ)。
    ///
    /// 責務: 版の無い行の `removeRequested` が無視されることを確認します。
    func testRemoveRequestedForNotDownloadedPrefectureIsIgnored() async throws {
        guard await harness.makeAppearedModel() else { return }

        harness.model.send(.removeRequested(Values.prefecture(1)))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertNil(harness.model.state.pendingRemoval)
    }

    /// 削除の確認を受けた時に取り込み中なら、確認を閉じるだけで削除しません。
    ///
    /// 責務: 取り込み中の `removeConfirmed` を確認します。
    func testRemoveConfirmedWhileImportingOnlyClosesConfirmation() async throws {
        guard await harness.makeAppearedModel() else { return }
        harness.model.send(.removeRequested(Values.prefecture(13)))
        XCTAssertEqual(harness.model.state.pendingRemoval, Values.prefecture(13))
        harness.imports.source.downloadGate.close()
        harness.model.send(.downloadRequested(Values.prefecture(47)))
        guard await harness.waitUntilImportIsBlocked(47) else { return }

        harness.model.send(.removeConfirmed)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertNil(harness.model.state.pendingRemoval)
        XCTAssertTrue(harness.imports.datasets.retiredPrefectures.isEmpty)
        XCTAssertEqual(harness.row(13).dataset, tokyo)
        XCTAssertFalse(harness.row(13).canRemove)
        harness.imports.source.downloadGate.open()
        _ = await harness.waitUntilIdle()
    }
}
