import Foundation
import XCTest
@testable import ProjectZD8

/// LiveTelemetryModel が回復中・一時停止中を専用の表示状態にし、復帰で取得中へ戻り、セッションを終了扱いにしないことを検証します。
@MainActor
final class LiveTelemetryModelPauseTests: XCTestCase {
    /// 各テストのモデル部品です。
    private var fixture: LiveTelemetryModelFixture?

    /// 動いている取得を止め、期限待ちを解放します。
    ///
    /// 責務: テストごとに応答待ちの要求・期限待ち・取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 回復中は一時停止のフェーズで回復中の状態を持ち、受信中としても終了としても扱われません。
    ///
    /// 責務: 確認要求の応答待ちの間の表示状態と、`sessionDidEnd` が呼ばれないことを確認します。
    func testRecoveringIsDedicatedPhaseNotReceivingNorEnded() async {
        let fixture = await makeLoaded()
        fixture.linkRecovery.schedule([true])
        await fixture.telemetry.release(.transportFailure)
        await fixture.telemetry.waitForSentRequests(3)
        await fixture.waitUntil("回復中") { fixture.model.state.pauseStatus?.isRecovering == true }

        XCTAssertEqual(fixture.model.state.phase, .paused)
        XCTAssertEqual(fixture.model.state.pauseStatus?.statusKey, "telemetry.status.recovering.prompt_resync")
        XCTAssertFalse(fixture.model.state.isReceiving)
        XCTAssertTrue(fixture.model.state.isConnectionActive)
        XCTAssertEqual(fixture.notifications.endReasons, [])
    }

    /// 回復に成功すると取得中(読み込み済み)へ戻り、一時停止の状態は消えます。
    ///
    /// 責務: 確認要求の正応答の後に表示状態が受信中へ戻り、終了の通知が無いことを確認します。
    func testResumeReturnsToReceiving() async {
        let fixture = await makeLoaded()
        fixture.linkRecovery.schedule([true])
        await fixture.telemetry.release(.transportFailure)
        await fixture.telemetry.release(.responded([2]))

        await fixture.waitUntil("受信中") { fixture.model.state.phase == .loaded && fixture.model.state.pauseStatus == nil }

        XCTAssertTrue(fixture.model.state.isReceiving)
        XCTAssertEqual(fixture.notifications.endReasons, [])
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [true])
    }

    /// 回復を使い切った一時停止中は、原因ごとの表示キーを持ち、セッションは終了扱いになりません。
    ///
    /// 責務: リンク断の一時停止の表示状態と、`sessionDidEnd` が呼ばれないことを確認します。
    func testPausedShowsCauseAndDoesNotEndSession() async {
        let fixture = await makeLoaded()
        await fixture.telemetry.release(.transportFailure)

        await fixture.waitUntil("一時停止") { fixture.model.state.pauseStatus?.isRecovering == false }

        XCTAssertEqual(fixture.model.state.phase, .paused)
        XCTAssertEqual(fixture.model.state.pauseStatus?.statusKey, "telemetry.status.paused.link_lost")
        XCTAssertFalse(fixture.model.state.isReceiving)
        XCTAssertEqual(fixture.notifications.endReasons, [])
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [true])
    }

    /// 一時停止中のユーザー停止は猶予を待たずに待機状態へ戻り、ユーザー切断を1回だけ通知します。
    ///
    /// 責務: 停止の通知が終了時刻なしのユーザー切断であることを確認します。
    func testStopDuringPauseEndsOnceAsUserDisconnected() async {
        let fixture = await makeLoaded()
        await fixture.telemetry.release(.transportFailure)
        await fixture.waitUntil("一時停止") { fixture.model.state.pauseStatus?.isRecovering == false }

        fixture.model.send(.stopRequested)
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

        XCTAssertNil(fixture.model.state.pauseStatus)
        XCTAssertEqual(fixture.notifications.endReasons, [.userDisconnected])
        XCTAssertEqual(fixture.notifications.endedAts, [nil])
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [true, false])
    }

    /// フォアグラウンド復帰とリンク復帰の操作は、一時停止中の取得ループへ復帰の契機として届きます。
    ///
    /// 責務: 2つの操作がそれぞれ再接続の試行を1回ずつ起こし、リンク断の操作は試行を起こさないことを確認します。
    func testForegroundAndLinkActionsWakePausedLoop() async {
        let fixture = await makeLoaded()
        await fixture.telemetry.release(.transportFailure)
        await fixture.waitUntil("一時停止") { fixture.model.state.pauseStatus?.isRecovering == false }
        let afterPause = fixture.linkRecovery.calls.count

        fixture.model.send(.adapterLinkAvailabilityChanged(isAvailable: false))
        await LiveTelemetryBoundedWaiter.settle()
        XCTAssertEqual(fixture.linkRecovery.calls.count, afterPause)
        fixture.model.send(.foregroundTransitionOccurred)
        await fixture.linkRecovery.waitForCalls(afterPause + 1)
        fixture.model.send(.adapterLinkAvailabilityChanged(isAvailable: true))
        await fixture.linkRecovery.waitForCalls(afterPause + 2)

        XCTAssertEqual(Array(fixture.linkRecovery.calls.suffix(2)), [.reconnectLink, .reconnectLink])
    }

    /// PID 0x0C だけで開始し、初回周回の正応答で読み込み済みにします。
    ///
    /// 責務: 後片付けの対象にしたモデル部品を、読み込み済みで次の要求を待つ状態で返します。
    /// - Returns: モデル部品。
    private func makeLoaded() async -> LiveTelemetryModelFixture {
        let fixture = LiveTelemetryModelFixture(catalog: LiveTelemetryTestDefinitions.standard([0x0C]))
        self.fixture = fixture
        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        await fixture.waitUntil("読み込み済み") { fixture.model.state.phase == .loaded }
        return fixture
    }
}
