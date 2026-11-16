import XCTest
@testable import ProjectZD8

/// `AdapterLinkVehicleConfirmationTransition` の初期化失敗後の再試行(予約と、待機明けの再初期化)を検証します。
@MainActor
final class AdapterLinkVehicleConfirmationTransitionInitializationRetryTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkVehicleConfirmationTransition(timing: .standard)

    /// 初期化を始められない条件の組(リンクが `ready` でない・リンク未開始・手動接続が使用中)です。
    private var blockedConditions: [AdapterLinkSupervisionConditions] {
        [F.conditions(linkState: .connecting), F.conditions(linkPreference: nil), F.conditions(isExternalAdapterUseActive: true)]
    }

    /// 初期化の失敗でリンクが `ready` なら、待機へ戻して60秒後の再初期化を予約します。
    ///
    /// 責務: `standby` と `.scheduleAdapterInitializationRetry(after: .seconds(60))` を確認します(仕様2)。
    func testInitializationFailedWithReadyLinkSchedulesRetry() {
        let result = transition.adapterInitializationFailed(from: .initializing(linkReadyAt: F.referenceDate), conditions: F.conditions())
        A.assertResult(result, state: .standby, effects: [.scheduleAdapterInitializationRetry(after: .seconds(60))])
    }

    /// 再試行の待機が明けたとき、待機でリンクが `ready` なら現在時刻を起点に初期化からやり直します。
    ///
    /// 責務: `initializing(linkReadyAt: now)` と初期化の作用になることを確認します(仕様2)。
    func testInitializationRetryElapsedInReadyStandbyReinitializes() {
        let now = F.date(500)
        let result = transition.adapterInitializationRetryElapsed(from: .standby, conditions: F.conditions(now: now))
        A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter])
    }

    /// 予約の発火時点で、待機以外の状態では何もしません。
    ///
    /// 責務: 待機以外の全状態で状態不変・作用なしであることを確認します(仕様2)。
    func testInitializationRetryElapsedOutsideStandbyIsIgnored() {
        for state in F.allStates where state != .standby {
            A.assertIgnored(transition.adapterInitializationRetryElapsed(from: state, conditions: F.conditions()), from: state, "\(state)")
        }
    }

    /// 予約の発火時点で、リンクが `ready` でない・リンク未開始・手動接続が使用中なら何もしません。
    ///
    /// 責務: 各条件で待機のまま作用なしであることを確認します(仕様2・4)。
    func testInitializationRetryElapsedWhenBlockedIsIgnored() {
        for conditions in blockedConditions {
            let result = transition.adapterInitializationRetryElapsed(from: .standby, conditions: conditions)
            A.assertIgnored(result, from: .standby, "\(conditions)")
        }
    }
}
