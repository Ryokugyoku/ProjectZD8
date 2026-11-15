import Foundation
import XCTest
@testable import ProjectZD8

/// LiveTelemetryModel が、ユーザーの[切断]と区別した理由付きの終了要求で、取得記録と終了通知へ同じ理由を渡すことを検証します。
///
/// 仕様: U2 受け入れ条件 9〜13。
@MainActor
final class LiveTelemetryModelEndRequestTests: XCTestCase {
    /// 各テストのモデル部品です。
    private var fixtures: [LiveTelemetryModelFixture] = []

    /// 動いている取得を止め、期限待ちを解放します。
    ///
    /// 責務: テストごとに応答待ちの要求・期限待ち・取得Taskを片付けます。
    override func tearDown() async throws {
        for fixture in fixtures { await fixture.tearDown() }
        fixtures.removeAll()
        try await super.tearDown()
    }

    /// 取得中の理由付きの終了要求は、その理由で取得記録を終え、同じ理由・終了時刻なし(処理した時刻)で終了を通知します。
    ///
    /// 責務: サインアウト・置き換え・接続断の3つの理由で、記録の終了原因と `sessionDidEnd` の理由が一致し、ユーザー切断にならないことを確認します。
    func testEndRequestedWhileReceivingUsesGivenReason() async {
        for reason in [ConnectionSessionEndReason.accountSignedOut, .superseded, .connectionLost] {
            let fixture = await makeLoaded()

            fixture.model.send(.endRequested(reason))
            await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

            XCTAssertEqual(fixture.notifications.endReasons, [reason], "\(reason)")
            XCTAssertEqual(fixture.notifications.endedAts, [nil], "\(reason)")
            let finishes = await fixture.recorder?.finishCalls ?? []
            XCTAssertEqual(finishReasons(finishes), [reason], "\(reason)")
        }
    }

    /// リンク断の一時停止中に理由付きの終了要求が届いても、猶予を待たずにその理由で終わります。
    ///
    /// 責務: 一時停止中の置き換えの終了要求で、記録の終了原因と通知の理由が `superseded` になることを確認します(仕様 10・13)。
    func testEndRequestedWhilePausedUsesGivenReason() async {
        let fixture = await makeLoaded()
        await fixture.telemetry.release(.transportFailure)
        await fixture.waitUntil("一時停止") { fixture.model.state.pauseStatus?.isRecovering == false }

        fixture.model.send(.endRequested(.superseded))
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

        XCTAssertEqual(fixture.notifications.endReasons, [.superseded])
        let finishes = await fixture.recorder?.finishCalls ?? []
        XCTAssertEqual(finishReasons(finishes), [.superseded])
    }

    /// ユーザーの[切断]は、取得記録と終了通知の両方でユーザー切断です。
    ///
    /// 責務: `.stopRequested` の記録の終了原因と通知の理由が `userDisconnected` で一致することを確認します(仕様 13)。
    func testStopRequestedIsUserDisconnectedForRecordingAndNotification() async {
        let fixture = await makeLoaded()

        fixture.model.send(.stopRequested)
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

        XCTAssertEqual(fixture.notifications.endReasons, [.userDisconnected])
        let finishes = await fixture.recorder?.finishCalls ?? []
        XCTAssertEqual(finishReasons(finishes), [.userDisconnected])
    }

    /// 記録の終了呼び出しから終了原因を取り出します。
    ///
    /// 責務: 記録ポートのスパイの終了呼び出しを、終了原因の列へ変換します。
    /// - Parameter calls: 終了呼び出し。
    /// - Returns: 終了原因(呼び出し順)。
    private func finishReasons(_ calls: [LiveTelemetryRecordingPortCall]) -> [ConnectionSessionEndReason] {
        calls.compactMap { if case let .finish(_, reason) = $0 { reason } else { nil } }
    }

    /// 記録ポート付きで PID 0x0C だけを開始し、初回周回の正応答で読み込み済みにします。
    ///
    /// 責務: 後片付けの対象にしたモデル部品を、読み込み済みで次の要求を待つ状態で返します。
    /// - Returns: モデル部品。
    private func makeLoaded() async -> LiveTelemetryModelFixture {
        let fixture = LiveTelemetryModelFixture(catalog: LiveTelemetryTestDefinitions.standard([0x0C]), recorder: LiveTelemetryRecordingPortSpy())
        fixtures.append(fixture)
        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        await fixture.waitUntil("読み込み済み") { fixture.model.state.phase == .loaded }
        return fixture
    }
}
