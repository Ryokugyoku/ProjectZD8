import XCTest
@testable import ProjectZD8

/// 同期画面の状態遷移を確認します。
@MainActor
final class SyncModelTests: XCTestCase {
    /// 責務: 条件が成り立つまで最大2秒待ちます。
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    /// 責務: 表示で購読を1回だけ始め、状態と最終同期日時を反映することを確認します。
    func testAppearedObservesStatusOnce() async {
        let port = SyncFakeCloudSyncPort()
        let model = SyncModel(sync: port)
        model.send(.appeared)
        model.send(.appeared)
        await waitUntil { model.state.status == .idle(lastSyncedAt: nil) }
        XCTAssertEqual(port.statusSubscriptionCount, 1)
        XCTAssertEqual(model.state.statusMessageKey, "sync.status.idle.never")

        let date = Date(timeIntervalSince1970: 1_000)
        port.emit(.idle(lastSyncedAt: date))
        await waitUntil { model.state.lastSyncedAt == date }
        port.emit(.failed(.network))
        await waitUntil { model.state.status == .failed(.network) }
        XCTAssertEqual(model.state.lastSyncedAt, date)
        XCTAssertEqual(model.state.statusMessageKey, "sync.status.failed")
        XCTAssertEqual(model.state.statusFailureMessageKey, "sync.failure.network")
    }

    /// 責務: 今すぐ同期の成功と型付きの失敗、閉じる操作を確認します。
    func testSyncNowSuccessAndFailure() async {
        let port = SyncFakeCloudSyncPort(syncNowError: .quotaExceeded)
        let model = SyncModel(sync: port)
        model.send(.appeared)
        await waitUntil { model.state.canSyncNow }

        model.send(.syncNowTapped)
        XCTAssertTrue(model.state.isSyncNowRunning)
        XCTAssertFalse(model.state.canSyncNow)
        await waitUntil { !model.state.isSyncNowRunning }
        XCTAssertEqual(port.syncNowCount, 1)
        XCTAssertEqual(model.state.syncNowFailure, .quotaExceeded)
        XCTAssertEqual(model.state.syncNowFailureMessageKey, "sync.failure.quotaExceeded")

        model.send(.failureDismissed)
        XCTAssertNil(model.state.syncNowFailure)
    }

    /// 責務: 利用不可の間は今すぐ同期を実行しないことを確認します。
    func testSyncNowIgnoredWhileUnavailable() async {
        let port = SyncFakeCloudSyncPort()
        let model = SyncModel(sync: port)
        model.send(.syncNowTapped)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(port.syncNowCount, 0)
        XCTAssertEqual(model.state.statusMessageKey, "sync.status.unavailable.temporarilyUnavailable")
    }

    /// 責務: 全データ削除の確認・取り消し・成功を確認します。
    func testEraseAllConfirmCancelAndSuccess() async {
        let port = SyncFakeCloudSyncPort()
        let model = SyncModel(sync: port)

        model.send(.eraseAllConfirmed) // 確認前は無視
        model.send(.eraseAllRequested)
        XCTAssertEqual(model.state.erasePhase, .confirming)
        model.send(.eraseAllCancelled)
        XCTAssertEqual(model.state.erasePhase, .idle)
        XCTAssertEqual(port.eraseCount, 0)

        model.send(.eraseAllRequested)
        model.send(.eraseAllConfirmed)
        XCTAssertEqual(model.state.erasePhase, .erasing)
        XCTAssertFalse(model.state.canEraseAll)
        await waitUntil { model.state.erasePhase == .completed }
        XCTAssertEqual(port.eraseCount, 1)
        model.send(.failureDismissed)
        XCTAssertEqual(model.state.erasePhase, .idle)
    }

    /// 責務: 全データ削除の失敗が型付きで残ることを確認します。
    func testEraseAllFailure() async {
        let model = SyncModel(sync: SyncFakeCloudSyncPort(eraseError: .network))
        model.send(.eraseAllRequested)
        model.send(.eraseAllConfirmed)
        await waitUntil { model.state.erasePhase == .failed(.network) }
        XCTAssertEqual(model.state.eraseFailureMessageKey, "sync.failure.network")
        model.send(.failureDismissed)
        XCTAssertEqual(model.state.erasePhase, .idle)
    }

    /// 責務: 全ての状態と失敗に文言キーがあることを確認します。
    func testLocalizationKeysCoverAllCases() {
        let statuses: [CloudSyncStatus] = [
            .unavailable(.noAccount), .unavailable(.restricted), .unavailable(.temporarilyUnavailable),
            .idle(lastSyncedAt: nil), .idle(lastSyncedAt: Date()), .syncing, .failed(.other),
        ]
        XCTAssertEqual(Set(statuses.map(SyncLocalizationKey.status)).count, statuses.count)
        let failures: [CloudSyncFailure] = [.network, .quotaExceeded, .integrity, .notFound, .other]
        XCTAssertEqual(Set(failures.map(SyncLocalizationKey.failure)).count, failures.count)
    }
}
