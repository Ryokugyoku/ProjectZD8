import Foundation
import XCTest
@testable import ProjectZD8

/// リンク断の途切れで、リンク可用性の通知(`notify(.linkRestored)` / `notify(.linkLost)`)が復帰の機会として失われないことを検証します。
///
/// 時間は手動の単調時計・実時刻clockと、テストが解放する確認要求の応答と期限待ちだけで進めます。
@MainActor
final class LiveTelemetryAcquisitionLoopLinkAvailabilityTests: XCTestCase {
    /// 猶予の3分です(ナノ秒)。
    private let grace = AcquisitionGracePeriodPolicy.gracePeriodNanoseconds
    /// 回復段階の試行回数の合計です。
    private let recoveryAttempts = AcquisitionStallPolicy.promptResyncAttemptLimit
        + AcquisitionStallPolicy.reinitializeFromResetAttemptLimit
        + AcquisitionStallPolicy.reconnectLinkAttemptLimit
    /// 各テストのループ部品です。
    private var fixture: LiveTelemetryAcquisitionLoopFixture?

    /// 動いている取得を止め、期限待ちを解放します。
    ///
    /// 責務: テストごとに応答待ちの要求・期限待ち・取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 回復段階の最中に届いたリンク復帰は、一時停止に入った時点で、定期試行を待たずに再接続を試させます。
    ///
    /// 責務: 回復段階の試行を使い切った直後に、期限待ちを解放しなくても再接続の試行が1回増えることを確認します(U2 受け入れ条件 5)。
    func testLinkRestoredDuringRecoveryAttemptsImmediatelyOnPause() async {
        let fixture = make()
        fixture.linkRecovery.schedule([true])
        let (collector, _) = await fixture.startAndInterrupt(cause: .linkLost)
        await fixture.waitForSentRequests(3)

        await fixture.loop.notify(.linkRestored)
        await fixture.telemetry.release(.timedOut)

        await fixture.linkRecovery.waitForCalls(recoveryAttempts + 1)
        XCTAssertEqual(fixture.linkRecovery.calls.last, .reconnectLink)
        XCTAssertNil(collector.termination)
    }

    /// 回復段階の最中にリンク復帰の後でリンク断が届いた場合は、一時停止に入っても定期試行の時刻まで試しません。
    ///
    /// 責務: 一時停止に入った時点でリンクが使えなければ、回復操作が増えないことを確認します(U2 受け入れ条件 5)。
    func testLinkRestoredThenLostDuringRecoveryWaitsForRetry() async {
        let fixture = make()
        fixture.linkRecovery.schedule([true])
        let (collector, _) = await fixture.startAndInterrupt(cause: .linkLost)
        await fixture.waitForSentRequests(3)

        await fixture.loop.notify(.linkRestored)
        await fixture.loop.notify(.linkLost)
        await fixture.telemetry.release(.timedOut)
        await fixture.waitForPause(of: collector)
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(fixture.linkRecovery.calls.count, recoveryAttempts)
    }

    /// リンク断の一時停止中に、最後の受信からちょうど猶予の時点でリンク復帰が届き再接続に成功すれば、同じセッションの新しい区間で続行します。
    ///
    /// 責務: リンク復帰の通知で再接続を試し、欠損(開始=最後の受信、原因=リンク断)を挟んで区間を再開することを確認します(U2 受け入れ条件 2)。
    func testLinkRestoredWithinGraceResumesWithLinkLostGap() async {
        let fixture = make()
        let (collector, lastReceived) = await fixture.startAndInterrupt(cause: .linkLost)
        await fixture.waitForPause(of: collector)
        fixture.linkRecovery.schedule([true])
        fixture.advanceClock(to: lastReceived + grace)

        await fixture.loop.notify(.linkRestored)
        await fixture.telemetry.release(.responded([5]))

        await fixture.assertContinued(
            collector, lastReceivedAt: LiveTelemetryAcquisitionLoopFixture.fixedNow, sentRequests: 4,
            segmentEndReason: .linkLost, gapCause: .linkLost
        )
        XCTAssertEqual(fixture.linkRecovery.calls.last, .reconnectLink)
    }

    /// 記録ポートのスパイ付きの部品を生成して後片付けの対象にします。
    ///
    /// 責務: 既定の記録ポートを持つループ部品を返します。
    /// - Returns: ループ部品。
    private func make() -> LiveTelemetryAcquisitionLoopFixture {
        let fixture = LiveTelemetryAcquisitionLoopFixture()
        self.fixture = fixture
        return fixture
    }
}
