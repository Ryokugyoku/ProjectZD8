import XCTest
@testable import ProjectZD8

/// リンク待ちの保持(リンクが `ready` でない間のユーザー切断の後)で、切断から3分(ちょうどを含む)以内にリンクが戻れば
/// 同じ走行として復帰時刻から見張りを始め、超えてから戻れば通常の検知を始め、待っている間はアダプターへ何も送らないことを検証します。
///
/// 仕様: U8 R4(U2 受け入れ条件 8 の改訂)。3分の経過は次のイベントが届いた時に判定します。
@MainActor
final class AdapterLinkHeldLinkWaitTransitionTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures
    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// ユーザーが切断した時刻です。
    private let stoppedAt = AdapterLinkSupervisionFixtures.date(100)
    /// 検証対象の遷移です(本番の時間定数)。
    private let transition = AdapterLinkHeldLinkWaitTransition(timing: .standard)

    /// リンク待ちの保持の状態です。
    private var awaitingLink: AdapterLinkHeldWatch { .awaitingLink(userStoppedAt: stoppedAt) }

    /// `ready` 以外のリンク状態です。
    private let nonReadyLinkStates: [AdapterLinkState] = [
        .connecting, .discovering, .awaitingPeripheral, .disconnected(.peripheralDisconnected(errorDescription: nil)),
    ]

    /// 本番のリンク待ちの上限は3分です。
    ///
    /// 責務: `AdapterLinkSupervisionTiming.standard.heldLinkWaitLimit` が180秒で、既定の生成でも180秒になることを確認します。
    func testStandardLimitIsThreeMinutes() {
        XCTAssertEqual(AdapterLinkSupervisionTiming.standard.heldLinkWaitLimit, 180)
        XCTAssertEqual(AdapterLinkSupervisionTiming(vehicleConfirmationWindow: 60, vehicleConfirmationInterval: 1).heldLinkWaitLimit, 180)
    }

    /// 上限以内の判定は、切断から上限ちょうどまでを含み、直後を含みません。
    ///
    /// 責務: 切断の時刻・179.999秒・180秒が以内、180.001秒が超えであることを確認します。
    func testIsWithinLimitBoundaries() {
        for elapsed in [0, 179.999, 180] {
            XCTAssertTrue(transition.isWithinLimit(userStoppedAt: stoppedAt, now: stoppedAt.addingTimeInterval(elapsed)), "\(elapsed)")
        }
        XCTAssertFalse(transition.isWithinLimit(userStoppedAt: stoppedAt, now: stoppedAt.addingTimeInterval(180.001)))
    }

    /// 上限以内(直前・ちょうど)に `ready` へ戻ったら、復帰の時刻から8時間の見張りを始めます。
    ///
    /// 責務: 179.999秒・180秒の `ready` で、見張り中(終わり=復帰時刻+8時間、連続無応答0)と見張りの確認1件になることを確認します。
    func testReadyWithinLimitStartsWatchFromReturnTime() {
        for elapsed in [179.999, 180] {
            let now = stoppedAt.addingTimeInterval(elapsed)
            let result = linkChanged(to: .ready, conditions: F.conditions(linkState: .connecting, now: now))
            A.assertResult(
                result, state: F.watching(noResponses: 0, endsAt: now.addingTimeInterval(F.heldWatchSeconds)),
                effects: [.confirmVehicle(.heldWatch)], "\(elapsed)"
            )
        }
    }

    /// 上限を超えて(直後に)`ready` へ戻ったら、復帰の時刻を窓の起点として初期化から検知を始めます。
    ///
    /// 責務: 180.001秒の `ready` で `.initializing(linkReadyAt: 復帰時刻)` と初期化の作用になることを確認します。
    func testReadyAfterLimitStartsDetection() {
        let now = stoppedAt.addingTimeInterval(180.001)
        let result = linkChanged(to: .ready, conditions: F.conditions(linkState: .connecting, now: now))
        A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter])
    }

    /// 手動接続の使用中に上限以内で `ready` へ戻ったら、確認を送らずに見張りの開始待ちにします(使い終えた時に始めます)。
    ///
    /// 責務: 180秒の `ready` で `.heldAfterUserStop(.awaitingStart)`・作用なしになることを確認します。
    func testReadyWithinLimitWhileExternalAdapterUseAwaitsStart() {
        let conditions = F.conditions(linkState: .connecting, now: stoppedAt.addingTimeInterval(180), isExternalAdapterUseActive: true)
        A.assertResult(linkChanged(to: .ready, conditions: conditions), state: .heldAfterUserStop(.awaitingStart), effects: [])
    }

    /// 手動接続の使用中に上限を超えて `ready` へ戻ったら、初期化せず待機へ戻ります。
    ///
    /// 責務: 180.001秒の `ready` で `.standby`・作用なしになることを確認します。
    func testReadyAfterLimitWhileExternalAdapterUseReturnsToStandby() {
        let conditions = F.conditions(linkState: .connecting, now: stoppedAt.addingTimeInterval(180.001), isExternalAdapterUseActive: true)
        A.assertResult(linkChanged(to: .ready, conditions: conditions), state: .standby, effects: [])
    }

    /// 上限以内の `ready` 以外への変化では、リンク待ちの保持のまま何も送りません。
    ///
    /// 責務: 各リンク状態への変化を 0秒・180秒で受けて、状態不変・作用なしであることを確認します。
    func testNonReadyChangeWithinLimitKeepsWaiting() {
        for elapsed in [0, 180.0] {
            for linkState in nonReadyLinkStates {
                let result = linkChanged(to: linkState, conditions: F.conditions(linkState: .connecting, now: stoppedAt.addingTimeInterval(elapsed)))
                A.assertIgnored(result, from: .heldAfterUserStop(awaitingLink), "\(elapsed) \(linkState)")
            }
        }
    }

    /// 上限を超えた `ready` 以外への変化では、保持を解いて待機へ戻ります(何も動いていないので作用なし)。
    ///
    /// 責務: 各リンク状態への変化を180.001秒で受けて、`.standby`・作用なしになることを確認します。
    func testNonReadyChangeAfterLimitReturnsToStandby() {
        for linkState in nonReadyLinkStates {
            let result = linkChanged(to: linkState, conditions: F.conditions(linkState: .connecting, now: stoppedAt.addingTimeInterval(180.001)))
            A.assertResult(result, state: .standby, effects: [], "\(linkState)")
        }
    }

    /// リンクを開始していない(接続対象が無い)時のリンク状態の変化は無視します。
    ///
    /// 責務: `linkPreference == nil` で、上限以内・超えの `ready` を受けても状態不変・作用なしであることを確認します。
    func testChangeWithoutLinkPreferenceIsIgnored() {
        for elapsed in [180, 180.001] {
            let conditions = F.conditions(linkPreference: nil, linkState: .connecting, now: stoppedAt.addingTimeInterval(elapsed))
            A.assertIgnored(linkChanged(to: .ready, conditions: conditions), from: .heldAfterUserStop(awaitingLink), "\(elapsed)")
        }
    }

    /// 注入したリンク待ちの上限で判定します。
    ///
    /// 責務: 上限60秒の時間定数で、60秒の `ready` が見張りの開始、60.001秒の `ready` が初期化になることを確認します。
    func testInjectedLimitIsUsed() {
        let timing = AdapterLinkSupervisionTiming(vehicleConfirmationWindow: 600, vehicleConfirmationInterval: 1, heldLinkWaitLimit: 60)
        let injected = AdapterLinkHeldLinkWaitTransition(timing: timing)
        let within = stoppedAt.addingTimeInterval(60)
        let after = stoppedAt.addingTimeInterval(60.001)

        let returned = injected.linkStateChanged(
            to: .ready, userStoppedAt: stoppedAt, watch: awaitingLink, conditions: F.conditions(linkState: .connecting, now: within)
        )
        XCTAssertEqual(returned.effects, [.confirmVehicle(.heldWatch)])
        let detected = injected.linkStateChanged(
            to: .ready, userStoppedAt: stoppedAt, watch: awaitingLink, conditions: F.conditions(linkState: .connecting, now: after)
        )
        A.assertResult(detected, state: .initializing(linkReadyAt: after), effects: [.initializeAdapter])
    }

    /// リンク待ちの保持でリンク状態が変わった時の遷移を返します。
    ///
    /// 責務: 固定の切断時刻とリンク待ちの保持で、本番の時間定数の遷移を呼びます。
    /// - Parameters:
    ///   - linkState: 変化後のリンク状態。
    ///   - conditions: 変化前のリンク状態と現在時刻を含む条件。
    /// - Returns: 遷移結果。
    private func linkChanged(to linkState: AdapterLinkState, conditions: AdapterLinkSupervisionConditions) -> AdapterLinkSupervisionTransitionResult {
        transition.linkStateChanged(to: linkState, userStoppedAt: stoppedAt, watch: awaitingLink, conditions: conditions)
    }
}
