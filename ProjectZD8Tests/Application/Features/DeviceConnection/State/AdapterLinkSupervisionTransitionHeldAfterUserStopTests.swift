import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTransition` が、ユーザー切断後の抑止状態で、同じリンク接続のあいだ
/// 初期化・検知・記録開始をせず、リンクを失った時だけ待機へ戻ることを検証します。
@MainActor
final class AdapterLinkSupervisionTransitionHeldAfterUserStopTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkSupervisionTransition()

    /// 抑止中に前面へ戻っても、リンクが ready のままなら何もしません。
    ///
    /// 責務: 状態不変・作用なしを確認します。
    func testAppDidBecomeActiveDoesNothingWhileHeld() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        let result = transition.result(from: held, on: .appDidBecomeActive, conditions: F.conditions())
        A.assertIgnored(result, from: held)
    }

    /// 抑止中に ready の再通知を受けても、何もしません。
    ///
    /// 責務: 状態不変・作用なしを確認します。
    func testRepeatedLinkReadyDoesNothingWhileHeld() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        let result = transition.result(from: held, on: .linkStateChanged(.ready), conditions: F.conditions())
        A.assertIgnored(result, from: held)
    }

    /// 抑止中にリンクが ready 以外へ変わると待機へ戻り、続く ready で初期化からやり直します。
    ///
    /// 責務: 巻き戻しの状態・作用と、再接続後の初期化開始を確認します。
    func testLinkLossWhileHeldReturnsToStandbyThenReconnectInitializes() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        let lost = transition.result(from: held, on: .linkStateChanged(.connecting), conditions: F.conditions())
        A.assertResult(lost, state: .standby, effects: [.cancelOperations, .dismissNotification])

        let ready = transition.result(from: lost.state, on: .linkStateChanged(.ready), conditions: F.conditions(linkState: .connecting))
        A.assertResult(ready, state: .initializing(linkReadyAt: F.referenceDate), effects: [.initializeAdapter])
    }

    /// 抑止中に手動使用の開始・終了を受けても、抑止のままで作用はありません。
    ///
    /// 責務: 開始と終了のどちらでも状態不変・作用なしを確認します。
    func testExternalAdapterUseKeepsHeldState() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        for event in [AdapterLinkSupervisionEvent.externalAdapterUseBegan, .externalAdapterUseEnded] {
            let result = transition.result(from: held, on: event, conditions: F.conditions())
            A.assertIgnored(result, from: held, "\(event)")
        }
    }

    /// 抑止中は、記録開始選択・初期化・確認・VIN読取・終了完了のイベントを無視します。
    ///
    /// 責務: それぞれのイベントで状態不変・作用なしを確認します。
    func testOtherEventsAreIgnoredWhileHeld() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        let events: [AdapterLinkSupervisionEvent] = [
            .recordingStartSelected,
            .adapterInitializationSucceeded(F.evidence),
            .adapterInitializationFailed,
            .vehicleConfirmationCompleted(.responding),
            .vehicleConfirmationFailed,
            .vehicleConfirmationIntervalElapsed,
            .vinReadCompleted(vin: F.vin, isAutomaticRecordingEnabled: true),
            .vinReadFailed(isAutomaticRecordingEnabled: true),
            .finishingDidComplete,
        ]
        for event in events {
            let result = transition.result(from: held, on: event, conditions: F.conditions())
            A.assertIgnored(result, from: held, "\(event)")
        }
    }

    /// 抑止中に稼働条件の変化でリンクを止めた時は、待機へ戻ります。
    ///
    /// 責務: 既定アダプターを外すとリンク停止と取り消しを伴い待機になることを確認します。
    func testOperatingConditionsStoppingLinkReturnsToStandby() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        let conditions = F.conditions(defaultAdapterPreference: nil)
        let result = transition.result(from: held, on: .operatingConditionsChanged, conditions: conditions)
        A.assertResult(result, state: .standby, effects: [.cancelOperations, .dismissNotification, .stopLink])
    }

    /// 抑止中に既定アダプターが別のBLEアダプターへ変わってリンクを張り直す時も、待機へ戻ります。
    ///
    /// 責務: 停止・新しいリンク開始を伴い待機になることを確認します。
    func testOperatingConditionsRestartingLinkReturnsToStandby() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        let conditions = F.conditions(defaultAdapterPreference: F.otherBLEPreference)
        let result = transition.result(from: held, on: .operatingConditionsChanged, conditions: conditions)
        A.assertResult(
            result,
            state: .standby,
            effects: [.cancelOperations, .dismissNotification, .stopLink, .prepareNotifications, .startLink(F.otherBLEPreference)]
        )
    }
}
