import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTransition` が、初期化の失敗で待機へ戻るときに再試行を予約することを検証します。
///
/// 再試行の効果は `AdapterLinkSupervisionEffect.scheduleAdapterInitializationRetry(after:)`、間隔は60秒です。
@MainActor
final class AdapterLinkSupervisionTransitionInitializationRetryTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkSupervisionTransition()

    /// 初期化中の状態です。
    private let initializing = AdapterLinkSupervisionState.initializing(linkReadyAt: F.referenceDate)

    /// 初期化の失敗でリンクが `ready` なら、待機へ戻して60秒後の再試行を予約します。
    ///
    /// 責務: 待機への遷移と `.scheduleAdapterInitializationRetry(after: .seconds(60))` を確認します(仕様2)。
    func testInitializationFailedWithReadyLinkSchedulesRetryInSixtySeconds() {
        let result = transition.result(from: initializing, on: .adapterInitializationFailed, conditions: F.conditions())
        A.assertResult(result, state: .standby, effects: [.scheduleAdapterInitializationRetry(after: .seconds(60))])
    }

    /// リンクが `ready` でない・リンク未開始・手動接続が使用中なら、待機へ戻すだけで再試行を予約しません。
    ///
    /// 責務: 各条件で、待機への遷移と作用なしを確認します(仕様5)。
    func testInitializationFailedWithoutReadyLinkSchedulesNothing() {
        let blocked = [
            F.conditions(linkState: .connecting),
            F.conditions(linkPreference: nil),
            F.conditions(isExternalAdapterUseActive: true),
        ]
        for conditions in blocked {
            let result = transition.result(from: initializing, on: .adapterInitializationFailed, conditions: conditions)
            A.assertResult(result, state: .standby, effects: [], "\(conditions)")
        }
    }

    /// 初期化中以外へ届いた古い初期化失敗は、再試行を予約せず状態も変えません。
    ///
    /// 責務: 初期化中以外の全状態で、状態不変・作用なしを確認します。
    func testInitializationFailedOutsideInitializingIsIgnored() {
        for state in F.allStates {
            if case .initializing = state { continue }
            A.assertIgnored(transition.result(from: state, on: .adapterInitializationFailed, conditions: F.conditions()), from: state, "\(state)")
        }
    }
}
