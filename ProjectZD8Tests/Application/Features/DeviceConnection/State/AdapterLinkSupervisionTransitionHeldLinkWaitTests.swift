import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTransition` が、リンク待ちの保持(`.heldAfterUserStop(.awaitingLink(userStoppedAt:))`)で、
/// リンクの復帰以外のイベントではアダプターへ何も送らず、稼働条件の変化は保持と同じく扱うことを検証します。
///
/// 仕様: U8 R4。リンク状態の変化そのものの分岐は `AdapterLinkHeldLinkWaitTransitionTests` が検証します。
@MainActor
final class AdapterLinkSupervisionTransitionHeldLinkWaitTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures
    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkSupervisionTransition()
    /// ユーザーが切断した時刻です。
    private let stoppedAt = AdapterLinkSupervisionFixtures.date(100)

    /// リンク待ちの保持の状態です。
    private var held: AdapterLinkSupervisionState { .heldAfterUserStop(.awaitingLink(userStoppedAt: stoppedAt)) }

    /// 監視が切断の時点に入れる記録の終了の確定・前面復帰・遅れて届いた確認や待ち明け・手動接続の開始と終了・記録開始の選択では、
    /// リンク待ちのまま何も送りません。
    ///
    /// 責務: それぞれのイベントを上限以内(30秒後)にリンクが接続中の条件で受けて、状態不変・作用なしであることを確認します。
    func testEventsWhileWaitingForLinkSendNothing() {
        let events: [AdapterLinkSupervisionEvent] = [
            .recordingEndSettled, .appDidBecomeActive, .vehicleConfirmationCompleted(.responding), .vehicleConfirmationCompleted(.noResponse),
            .vehicleConfirmationFailed, .vehicleConfirmationIntervalElapsed, .externalAdapterUseBegan, .externalAdapterUseEnded,
            .recordingStartSelected, .finishingDidComplete,
        ]
        for event in events {
            let conditions = F.conditions(linkState: .connecting, now: stoppedAt.addingTimeInterval(30), isForeground: true)
            A.assertIgnored(transition.result(from: held, on: event, conditions: conditions), from: held, "\(event)")
        }
    }

    /// 上限を超えた後の前面復帰でも、リンクが戻っていなければ何もしません(3分の経過はリンクの変化で判定します)。
    ///
    /// 責務: 180.001秒後の前面復帰で、状態不変・作用なしであることを確認します。
    func testForegroundAfterLimitWithoutLinkDoesNothing() {
        let conditions = F.conditions(linkState: .connecting, now: stoppedAt.addingTimeInterval(180.001), isForeground: true)
        A.assertIgnored(transition.result(from: held, on: .appDidBecomeActive, conditions: conditions), from: held)
    }

    /// 稼働条件の変化でリンクを止める時は、保持と同じく待機へ戻ります。
    ///
    /// 責務: 既定アダプターを外すと取り消し・取り下げ・リンク停止を伴って `.standby` になることを確認します。
    func testOperatingConditionsStoppingLinkReturnsToStandby() {
        let conditions = F.conditions(defaultAdapterPreference: nil, linkState: .connecting, now: stoppedAt.addingTimeInterval(30))
        let result = transition.result(from: held, on: .operatingConditionsChanged, conditions: conditions)
        A.assertResult(result, state: .standby, effects: [.cancelOperations, .dismissNotification, .stopLink])
    }

    /// リンク待ちの保持でも、監視全体の遷移からリンクの復帰が振り分けられ、上限以内なら復帰時刻から見張りを始めます。
    ///
    /// 責務: 180秒の `ready` で、見張り中(終わり=復帰時刻+8時間)と見張りの確認1件になることを確認します。
    func testLinkReadyWithinLimitIsRoutedToWatchStart() {
        let now = stoppedAt.addingTimeInterval(180)
        let result = transition.result(from: held, on: .linkStateChanged(.ready), conditions: F.conditions(linkState: .connecting, now: now))
        A.assertResult(result, state: F.watching(endsAt: now.addingTimeInterval(F.heldWatchSeconds)), effects: [.confirmVehicle(.heldWatch)])
    }

    /// 監視全体の遷移でも、注入したリンク待ちの上限で判定します。
    ///
    /// 責務: 上限30秒の時間定数で、30.001秒の `ready` が初期化になることを確認します。
    func testInjectedLimitIsUsedBySupervisionTransition() {
        let timing = AdapterLinkSupervisionTiming(vehicleConfirmationWindow: 600, vehicleConfirmationInterval: 1, heldLinkWaitLimit: 30)
        let now = stoppedAt.addingTimeInterval(30.001)
        let result = AdapterLinkSupervisionTransition(timing: timing).result(
            from: held, on: .linkStateChanged(.ready), conditions: F.conditions(linkState: .connecting, now: now)
        )
        A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter])
    }

    /// ユーザー切断でリンク待ちの保持に入る時は、切断の時刻を覚えます。
    ///
    /// 責務: リンクが接続中の記録中に `recordingDidFinish(.userDisconnected)` を受けると、
    /// `.heldAfterUserStop(.awaitingLink(userStoppedAt: 切断時刻))` と通知の取り下げだけになることを確認します。
    func testUserDisconnectWithoutReadyLinkRemembersStopTime() {
        let result = transition.result(
            from: .recording(F.detectedVehicle),
            on: .recordingDidFinish(endReason: .userDisconnected),
            conditions: F.conditions(linkState: .connecting, now: stoppedAt)
        )
        A.assertResult(result, state: held, effects: [.dismissNotification])
    }
}
