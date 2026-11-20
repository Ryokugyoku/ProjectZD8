import XCTest
@testable import ProjectZD8

/// `AdapterLinkVehicleConfirmationTransition.appDidBecomeActive(from:conditions:)` の前面復帰による再開と窓の取り直しを、全状態について検証します。
@MainActor
final class AdapterLinkVehicleConfirmationTransitionForegroundTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures
    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkVehicleConfirmationTransition(timing: .standard)

    /// リンクが `ready` の待機で前面復帰したら、その時刻を起点に初期化からやり直します。
    ///
    /// 責務: `initializing(linkReadyAt: now)` と初期化の作用になることを確認します。
    func testAppDidBecomeActiveInReadyStandbyStartsInitialization() {
        let now = F.date(900)
        let result = transition.appDidBecomeActive(from: .standby, conditions: F.conditions(linkState: .ready, now: now))
        A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter])
    }

    /// リンクが `ready` でない・リンク未開始の待機では、前面復帰しても何もしません。
    ///
    /// 責務: 非 `ready` の待機と、接続対象のない `ready` の待機で無視されることを確認します。
    func testAppDidBecomeActiveInStandbyWithoutReadyLinkIsIgnored() {
        let variants = [
            F.conditions(linkState: .connecting),
            F.conditions(linkState: .disconnected(.bluetoothPoweredOff)),
            F.conditions(linkPreference: nil, linkState: .ready),
        ]
        for conditions in variants {
            A.assertIgnored(transition.appDidBecomeActive(from: .standby, conditions: conditions), from: .standby, "\(conditions)")
        }
    }

    /// 休止中に前面復帰したら、その時刻から10分の窓を取り直して確認を再開します。
    ///
    /// 責務: 窓の終了時刻=復帰時刻+10分・回数1・低頻度確認中・判定結果の引継ぎと再確認の作用を確認します。
    func testAppDidBecomeActiveWhilePausedResumesWithNewWindow() {
        let paused = F.confirmation(windowEndsAt: F.date(600), attemptCount: F.maximumAttempts, phase: .paused)
        let now = F.date(1_000)
        let result = transition.appDidBecomeActive(from: .confirmingVehicle(paused), conditions: F.conditions(now: now))
        let resumed = F.confirmation(windowEndsAt: now.addingTimeInterval(F.windowSeconds), attemptCount: 1, phase: .probing)
        A.assertResult(result, state: .confirmingVehicle(resumed), effects: [.confirmVehicle(.adapterMaximum)])
    }

    /// 確認中(`.probing`)に前面へ戻った時、窓が既に切れていたら(終了時刻ちょうどを含む)、その時刻から10分の窓を取り直して確認を続けます。
    ///
    /// 責務: 窓の終了時刻ちょうど・直後で、窓の終了時刻=復帰時刻+10分・回数1・低頻度確認中になり、休止しないことを確認します(U3 受け入れ条件 5b)。
    func testAppDidBecomeActiveWhileProbingAfterWindowEndRenewsWindow() {
        let probing = F.confirmation(windowEndsAt: F.date(600), attemptCount: 7, phase: .probing)
        for now in [F.date(600), F.date(601)] {
            let result = transition.appDidBecomeActive(from: .confirmingVehicle(probing), conditions: F.conditions(now: now))
            let renewed = F.confirmation(windowEndsAt: now.addingTimeInterval(F.windowSeconds), attemptCount: 1, phase: .probing)
            XCTAssertEqual(result.state, .confirmingVehicle(renewed), "\(now)")
            XCTAssertFalse(result.effects.contains(.initializeAdapter), "\(now)")
        }
    }

    /// 確認中(`.probing`)に前面へ戻った時、窓の内(終了時刻の直前)なら確認を重複させず、状態も変えません。
    ///
    /// 責務: 窓の終了時刻の1ミリ秒前の前面復帰が無視されることを確認します(U3 受け入れ条件 5)。
    func testAppDidBecomeActiveWhileProbingInsideWindowIsIgnored() {
        let probing = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(windowEndsAt: F.date(600), attemptCount: 7, phase: .probing))
        A.assertIgnored(transition.appDidBecomeActive(from: probing, conditions: F.conditions(now: F.date(599.999))), from: probing)
    }

    /// 初期化中・低頻度確認中(窓の内)・検知済み・記録中・終了中では、前面復帰しても状態を変えません。
    ///
    /// 責務: 前面復帰で確認や初期化が二重に走らないことを確認します(低頻度確認中は窓の内の時刻で確認します)。
    func testAppDidBecomeActiveInOtherStatesIsIgnored() {
        let paused = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(phase: .paused))
        for state in F.allStates where state != .standby && state != paused {
            A.assertIgnored(transition.appDidBecomeActive(from: state, conditions: F.conditions()), from: state, "\(state)")
        }
    }
}
