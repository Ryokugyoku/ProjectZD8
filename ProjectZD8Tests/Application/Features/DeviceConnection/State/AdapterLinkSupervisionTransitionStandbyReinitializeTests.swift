import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTransition` が、リンクが `ready` のまま待機に残る状況から再初期化を始めることを検証します。
///
/// アダプターは常時給電で BLE を保つため、再接続や前面復帰を待たずに、手動接続の終了と記録終了後に初期化をやり直す必要があります。
@MainActor
final class AdapterLinkSupervisionTransitionStandbyReinitializeTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkSupervisionTransition()

    /// 初期化を始められない条件の組(リンクが `ready` でない・リンク未開始・手動接続が使用中)です。
    private var blockedConditions: [AdapterLinkSupervisionConditions] {
        [
            F.conditions(linkState: .connecting),
            F.conditions(linkState: .disconnected(.peripheralDisconnected(errorDescription: nil))),
            F.conditions(linkPreference: nil),
            F.conditions(isExternalAdapterUseActive: true),
        ]
    }

    /// 待機でリンクが `ready` のとき、手動接続の終了ですぐ再初期化を始めます。
    ///
    /// 責務: 待機から `.initializing(linkReadyAt: now)` と `.initializeAdapter` になることを確認します(仕様1)。
    func testExternalAdapterUseEndedInStandbyReinitializesWhenLinkReady() {
        let now = F.date(123)
        let result = transition.result(from: .standby, on: .externalAdapterUseEnded, conditions: F.conditions(now: now))
        A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter])
    }

    /// 前面かどうかに関係なく、手動接続の終了で再初期化を始めます。
    ///
    /// 責務: 前面・背面のどちらでも同じ結果になることを確認します(仕様1)。
    func testExternalAdapterUseEndedReinitializesInForegroundAndBackground() {
        let now = F.date(9)
        for isForeground in [false, true] {
            let result = transition.result(
                from: .standby, on: .externalAdapterUseEnded, conditions: F.conditions(now: now, isForeground: isForeground)
            )
            A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter], "foreground=\(isForeground)")
        }
    }

    /// リンクが `ready` でない・リンク未開始・手動接続がまだ使用中なら、手動接続が終わっても何も始めません。
    ///
    /// 責務: 初期化を始められない各条件で、待機のまま作用なしであることを確認します(仕様5)。
    func testExternalAdapterUseEndedInStandbyDoesNothingWhenBlocked() {
        for conditions in blockedConditions {
            let result = transition.result(from: .standby, on: .externalAdapterUseEnded, conditions: conditions)
            A.assertIgnored(result, from: .standby, "\(conditions)")
        }
    }

    /// 待機以外(初期化中・確認中・検知済み・記録中・終了中)では、手動接続が終わっても状態も作用も変えません。
    ///
    /// 責務: 進行中の処理を再初期化で壊さないことを確認します(仕様1の範囲外)。
    func testExternalAdapterUseEndedOutsideStandbyIsIgnored() {
        for state in F.allStates where state != .standby {
            let result = transition.result(from: state, on: .externalAdapterUseEnded, conditions: F.conditions())
            A.assertIgnored(result, from: state, "\(state)")
        }
    }

    /// ユーザー切断後の保持は、手動接続の終了でこれまでどおり見張りを始めます(再初期化にはしません)。
    ///
    /// 責務: 開始待ちの保持から、時刻+8時間の見張りと見張りの確認1件になることを確認します(仕様6の回帰)。
    func testExternalAdapterUseEndedInHeldAfterUserStopStillStartsWatch() {
        let now = F.date(45)
        let result = transition.result(from: .heldAfterUserStop(.awaitingStart), on: .externalAdapterUseEnded, conditions: F.conditions(now: now))
        A.assertResult(result, state: F.watching(endsAt: now.addingTimeInterval(F.heldWatchSeconds)), effects: [.confirmVehicle(.heldWatch)])
    }

    /// 保持中に手動接続が終わっても、条件を満たさなければ開始待ちのままです。
    ///
    /// 責務: 初期化を始められない各条件で、保持が不変・作用なしであることを確認します(仕様5・6の回帰)。
    func testExternalAdapterUseEndedInHeldAfterUserStopDoesNothingWhenBlocked() {
        let held = AdapterLinkSupervisionState.heldAfterUserStop(.awaitingStart)
        for conditions in blockedConditions {
            A.assertIgnored(transition.result(from: held, on: .externalAdapterUseEnded, conditions: conditions), from: held, "\(conditions)")
        }
    }

    /// 記録終了後の確定で、待機でリンクが `ready` なら再初期化を始めます。
    ///
    /// 責務: `recordingEndSettled` から `.initializing(linkReadyAt: now)` と `.initializeAdapter` になることを確認します(仕様4の回帰)。
    func testRecordingEndSettledInStandbyReinitializesWhenLinkReady() {
        let now = F.date(77)
        let result = transition.result(from: .standby, on: .recordingEndSettled, conditions: F.conditions(now: now))
        A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter])
    }

    /// 記録終了後の確定でも、始められない条件では何も始めません。
    ///
    /// 責務: 各条件で、待機のまま作用なしであることを確認します(仕様4・5の回帰)。
    func testRecordingEndSettledInStandbyDoesNothingWhenBlocked() {
        for conditions in blockedConditions {
            A.assertIgnored(transition.result(from: .standby, on: .recordingEndSettled, conditions: conditions), from: .standby, "\(conditions)")
        }
    }
}
