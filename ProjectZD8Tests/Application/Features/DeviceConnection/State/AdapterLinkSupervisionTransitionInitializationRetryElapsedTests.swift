import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTransition` が、初期化再試行の予約が発火した時点の条件を判定することを検証します。
///
/// 条件は「待機・リンク `ready`・手動接続が使っていない」の3つで、1つでも欠けたら何もしません。
@MainActor
final class AdapterLinkSupervisionTransitionInitializationRetryElapsedTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkSupervisionTransition()

    /// 3条件を満たす待機では、現在時刻を起点に再初期化を始めます。
    ///
    /// 責務: 待機から `.initializing(linkReadyAt: now)` と `.initializeAdapter` になることを確認します。
    func testElapsedInStandbyWithAllConditionsReinitializes() {
        let now = F.date(60)
        let result = transition.result(from: .standby, on: .adapterInitializationRetryElapsed, conditions: F.conditions(now: now))
        A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter])
    }

    /// リンクが `ready` でない・リンク未開始・手動接続が使用中のいずれかなら、何もしません。
    ///
    /// 責務: 欠けた条件ごとに、待機のまま作用なしであることを確認します。
    func testElapsedWithMissingConditionDoesNothing() {
        let missing = [
            F.conditions(linkState: .connecting),
            F.conditions(linkState: .disconnected(.peripheralDisconnected(errorDescription: nil))),
            F.conditions(linkPreference: nil),
            F.conditions(isExternalAdapterUseActive: true),
        ]
        for conditions in missing {
            A.assertIgnored(transition.result(from: .standby, on: .adapterInitializationRetryElapsed, conditions: conditions), from: .standby, "\(conditions)")
        }
    }

    /// 待機以外(初期化中・確認中・検知済み・記録中・終了中・保持中)では、全条件を満たしても何もしません。
    ///
    /// 責務: 進行中の処理を再初期化で壊さないことを確認します。
    func testElapsedOutsideStandbyDoesNothing() {
        for state in F.allStates + [.heldAfterUserStop(.awaitingStart)] where state != .standby {
            A.assertIgnored(transition.result(from: state, on: .adapterInitializationRetryElapsed, conditions: F.conditions()), from: state, "\(state)")
        }
    }
}
