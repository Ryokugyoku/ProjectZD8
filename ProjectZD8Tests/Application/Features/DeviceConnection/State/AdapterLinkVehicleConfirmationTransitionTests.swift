import XCTest
@testable import ProjectZD8

/// `AdapterLinkVehicleConfirmationTransition` の初期化・車両確認・再確認・前面復帰を、全状態と境界値で検証します。
@MainActor
final class AdapterLinkVehicleConfirmationTransitionTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures
    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkVehicleConfirmationTransition(timing: .standard)

    /// 初期化の成功で、リンク `ready` の時刻から10分の窓を開き、通常のタイムアウトで最初の確認をします。
    ///
    /// 責務: 確認窓の終了時刻・確認回数1・低頻度確認中・判定結果の引継ぎ・`.standard` の確認を確認します。
    func testInitializationSucceededOpensWindowFromLinkReadyTime() {
        let readyAt = F.date(5)
        let result = transition.adapterInitializationSucceeded(F.evidence, from: .initializing(linkReadyAt: readyAt))
        let expected = F.confirmation(windowEndsAt: readyAt.addingTimeInterval(F.windowSeconds), attemptCount: 1, phase: .probing)
        A.assertResult(result, state: .confirmingVehicle(expected), effects: [.confirmVehicle(.standard)])
    }

    /// 初期化中以外で届いた初期化成功は無視します(古い結果)。
    ///
    /// 責務: 待機・確認中・休止中・検知済み・記録中・終了中で状態も作用も変えないことを確認します。
    func testInitializationSucceededOutsideInitializingIsIgnored() {
        for state in F.allStates {
            if case .initializing = state { continue }
            A.assertIgnored(transition.adapterInitializationSucceeded(F.otherEvidence, from: state), from: state, "\(state)")
        }
    }

    /// 初期化の失敗で待機へ戻り、検知・通知・リンク停止にはなりません。
    ///
    /// 責務: リンクが `ready` でない・リンク未開始・手動接続が使用中の初期化中から、作用なしで `standby` へ戻ることを確認します。
    func testInitializationFailedReturnsToStandbyWithoutEffects() {
        let blocked = [F.conditions(linkState: .connecting), F.conditions(linkPreference: nil), F.conditions(isExternalAdapterUseActive: true)]
        for conditions in blocked {
            let result = transition.adapterInitializationFailed(from: .initializing(linkReadyAt: F.referenceDate), conditions: conditions)
            A.assertResult(result, state: .standby, effects: [], "\(conditions)")
        }
    }

    /// 初期化中以外で届いた初期化失敗は無視します。
    ///
    /// 責務: 確認中や検知済みへ古い失敗が届いても待機へ巻き戻さないことを確認します。
    func testInitializationFailedOutsideInitializingIsIgnored() {
        for state in F.allStates {
            if case .initializing = state { continue }
            A.assertIgnored(transition.adapterInitializationFailed(from: state, conditions: F.conditions()), from: state, "\(state)")
        }
    }

    /// 低頻度確認中にECUが応答したら検知済み(VIN読取中)へ移り、VINを読みます。通知はまだ出しません。
    ///
    /// 責務: 判定結果を引き継いだVINなしの検知と `readVIN` の作用を確認します。
    func testRespondingWhileProbingDetectsVehicle() {
        let state = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: 7))
        let result = transition.vehicleConfirmationCompleted(.responding, from: state, conditions: F.conditions(now: F.date(200)))
        let vehicle = AdapterLinkDetectedVehicle(adapterProbeEvidence: F.evidence, vin: nil)
        A.assertResult(result, state: .vehicleDetected(vehicle, phase: .readingVIN), effects: [.readVIN])
    }

    /// 窓の中で、最短間隔以上かかった無応答なら、固定の待機を挟まずに回数を1つ進めてアダプター最大タイムアウトで次の確認を送ります。
    ///
    /// 責務: 窓の開始直後と終了直前(1ミリ秒前)、経過1秒ちょうど・30秒で、`.confirmVehicle(.adapterMaximum)` だけが出ることを確認します(U3 受け入れ条件 1・2・3)。
    func testNoResponseInsideWindowConfirmsAgainWithoutFixedWait() {
        let state = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: 1))
        for now in [F.date(30), F.date(F.windowSeconds - 0.001)] {
            for elapsed in [F.intervalSeconds, 30] {
                let conditions = F.conditions(now: now, lastVehicleConfirmationSentAt: now.addingTimeInterval(-elapsed))
                let result = transition.vehicleConfirmationCompleted(.noResponse, from: state, conditions: conditions)
                A.assertResult(
                    result, state: .confirmingVehicle(F.confirmation(attemptCount: 2)), effects: [.confirmVehicle(.adapterMaximum)], "\(now) \(elapsed)"
                )
            }
        }
    }

    /// 窓の中で、最短間隔より早く返った無応答なら、残り時間だけ待つ予約をし、まだ確認を送りません。
    ///
    /// 責務: 経過0秒・0.25秒・0.999秒で、予約が1件だけで、長さが残り時間(誤差2マイクロ秒以内)で、状態が変わらないことを確認します(U3 受け入れ条件 3)。
    func testNoResponseBeforeMinimumIntervalSchedulesRemainder() {
        let state = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: 1))
        let now = F.date(30)
        for elapsed in [0, 0.25, 0.999] {
            let conditions = F.conditions(now: now, lastVehicleConfirmationSentAt: now.addingTimeInterval(-elapsed))
            let result = transition.vehicleConfirmationCompleted(.noResponse, from: state, conditions: conditions)
            XCTAssertEqual(result.state, state, "\(elapsed)")
            XCTAssertEqual(result.effects.count, 1, "\(elapsed)")
            guard case let .scheduleVehicleConfirmation(after: wait)? = result.effects.first else {
                XCTFail("待機の予約ではない: \(result.effects) \(elapsed)")
                continue
            }
            let expected = Duration.microseconds(Int64(((F.intervalSeconds - elapsed) * 1_000_000).rounded()))
            XCTAssertLessThanOrEqual(max(wait - expected, expected - wait), .microseconds(2), "\(wait) \(elapsed)")
        }
    }

    /// 前面にいる間は、窓切れ(終了時刻ちょうど・直後)の無応答でも休止せず、その時刻から窓を取り直して確認を続けます。
    ///
    /// 責務: `isForeground` の時に、窓の終了時刻=受け取った時刻+10分・回数1で、アダプター最大タイムアウトの確認が出ることを確認します(U3 受け入れ条件 6)。
    func testNoResponseAfterWindowEndWhileForegroundRenewsWindow() {
        let confirmation = F.confirmation(attemptCount: 3)
        for now in [F.date(F.windowSeconds), F.date(F.windowSeconds + 0.001)] {
            let conditions = F.conditions(now: now, isForeground: true, lastVehicleConfirmationSentAt: now.addingTimeInterval(-30))
            let result = transition.vehicleConfirmationCompleted(.noResponse, from: .confirmingVehicle(confirmation), conditions: conditions)
            let renewed = F.confirmation(windowEndsAt: now.addingTimeInterval(F.windowSeconds), attemptCount: 1, phase: .probing)
            A.assertResult(result, state: .confirmingVehicle(renewed), effects: [.confirmVehicle(.adapterMaximum)], "\(now)")
        }
    }

    /// 窓の終了時刻ちょうど・それ以降の背面の無応答は、休止せず窓後の60秒間隔で確認を続けます。
    ///
    /// 責務: 10分ちょうど・10分+1ミリ秒で、確認直後なら状態を変えず60秒後の確認予約だけが出ることを確認します。
    func testNoResponseAtOrAfterWindowEndContinuesAtExtendedInterval() {
        let confirmation = F.confirmation(attemptCount: 3)
        for now in [F.date(F.windowSeconds), F.date(F.windowSeconds + 0.001)] {
            let conditions = F.conditions(now: now, lastVehicleConfirmationSentAt: now)
            let result = transition.vehicleConfirmationCompleted(.noResponse, from: .confirmingVehicle(confirmation), conditions: conditions)
            A.assertResult(result, state: .confirmingVehicle(confirmation), effects: [.scheduleVehicleConfirmation(after: .seconds(60))], "\(now)")
        }
    }

    /// 背面では、時計が進まなくても600回目の確認が無応答なら休止せず、窓後の60秒間隔の予約へ移ります。599回目の無応答では600回目を送ります。
    ///
    /// 責務: 回数上限の直前(599回目→600回目)と到達(600回目→60秒後の予約)の境界を背面で確認します(U3 受け入れ条件 4 を窓後継続へ改定)。
    func testNoResponseHonorsAttemptLimitWithFrozenClockInBackground() {
        let conditions = F.conditions(now: F.referenceDate, isForeground: false, lastVehicleConfirmationSentAt: F.date(-F.intervalSeconds))
        let beforeLimit = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: F.maximumAttempts - 1))
        let confirmed = transition.vehicleConfirmationCompleted(.noResponse, from: beforeLimit, conditions: conditions)
        A.assertResult(confirmed, state: .confirmingVehicle(F.confirmation(attemptCount: F.maximumAttempts)), effects: [.confirmVehicle(.adapterMaximum)])

        let atLimit = F.confirmation(attemptCount: F.maximumAttempts)
        let sent = F.conditions(now: F.referenceDate, isForeground: false, lastVehicleConfirmationSentAt: F.referenceDate)
        let extended = transition.vehicleConfirmationCompleted(.noResponse, from: .confirmingVehicle(atLimit), conditions: sent)
        A.assertResult(extended, state: .confirmingVehicle(atLimit), effects: [.scheduleVehicleConfirmation(after: .seconds(60))])
    }

    /// 前面では、時計が進まず600回目の確認が無応答でも休止せず、その時刻から窓と回数(1)を取り直して確認を続けます。
    /// 599回目の無応答では、窓を取り直さずに600回目を送ります。
    ///
    /// 責務: 回数上限の直前と到達の境界を前面で確認します(U8 R6。仕様「前面にいる間は休止に入らない」)。
    func testNoResponseAtAttemptLimitWithFrozenClockInForegroundRenewsWindow() {
        let now = F.referenceDate
        let conditions = F.conditions(now: now, isForeground: true, lastVehicleConfirmationSentAt: F.date(-F.intervalSeconds))
        let beforeLimit = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: F.maximumAttempts - 1))
        let confirmed = transition.vehicleConfirmationCompleted(.noResponse, from: beforeLimit, conditions: conditions)
        A.assertResult(confirmed, state: .confirmingVehicle(F.confirmation(attemptCount: F.maximumAttempts)), effects: [.confirmVehicle(.adapterMaximum)])

        let atLimit = F.confirmation(attemptCount: F.maximumAttempts)
        let renewedResult = transition.vehicleConfirmationCompleted(.noResponse, from: .confirmingVehicle(atLimit), conditions: conditions)
        let renewed = F.confirmation(windowEndsAt: now.addingTimeInterval(F.windowSeconds), attemptCount: 1, phase: .probing)
        A.assertResult(renewedResult, state: .confirmingVehicle(renewed), effects: [.confirmVehicle(.adapterMaximum)])
    }

    /// 低頻度確認中以外で届いた確認結果は、応答ありでも無視します。
    ///
    /// 責務: 休止中・待機・初期化中・検知済み・記録中・終了中で検知にも予約にもならないことを確認します。
    func testConfirmationCompletedOutsideProbingIsIgnored() {
        for state in F.allStates where state != .confirmingVehicle(F.confirmation(phase: .probing)) {
            for outcome in [VehicleResponseOutcome.responding, .noResponse] {
                let result = transition.vehicleConfirmationCompleted(outcome, from: state, conditions: F.conditions(now: F.referenceDate))
                A.assertIgnored(result, from: state, "\(state) \(outcome)")
            }
        }
    }

    /// 待機が終わると、窓の中なら回数を1つ進めてアダプター最大タイムアウトで再確認します。
    ///
    /// 責務: 窓の直前(1ミリ秒前)と19回目→20回目の境界で `.adapterMaximum` の確認になることを確認します。
    func testIntervalElapsedInsideLimitsRechecksWithAdapterMaximum() {
        let early = F.confirmation(attemptCount: 1)
        let resultEarly = transition.vehicleConfirmationIntervalElapsed(from: .confirmingVehicle(early), conditions: F.conditions(now: F.date(30)))
        A.assertResult(resultEarly, state: .confirmingVehicle(F.confirmation(attemptCount: 2)), effects: [.confirmVehicle(.adapterMaximum)])

        let last = F.confirmation(attemptCount: F.maximumAttempts - 1)
        let resultLast = transition.vehicleConfirmationIntervalElapsed(
            from: .confirmingVehicle(last), conditions: F.conditions(now: F.date(F.windowSeconds - 0.001))
        )
        let expected = F.confirmation(attemptCount: F.maximumAttempts)
        A.assertResult(resultLast, state: .confirmingVehicle(expected), effects: [.confirmVehicle(.adapterMaximum)])
    }

    /// 待機が終わった時点で窓を過ぎていても、休止せず確認を送ります。
    ///
    /// 責務: 10分ちょうど・それ以降で、状態を変えず `.confirmVehicle(.adapterMaximum)` が出ることを確認します。
    func testIntervalElapsedAtOrAfterWindowEndConfirmsWithoutPausing() {
        for now in [F.date(F.windowSeconds), F.date(F.windowSeconds + 30)] {
            let state = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: 4))
            let result = transition.vehicleConfirmationIntervalElapsed(from: state, conditions: F.conditions(now: now))
            A.assertResult(result, state: state, effects: [.confirmVehicle(.adapterMaximum)], "\(now)")
        }
    }

    /// 背面では、600回確認した後の待ち明けで、時計が進んでいなくても休止せず確認を送ります。
    ///
    /// 責務: 回数上限の境界(600回目の後)を背面で確認します(U3 受け入れ条件 4 を窓後継続へ改定)。
    func testIntervalElapsedAfterAttemptLimitConfirmsInBackground() {
        let state = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: F.maximumAttempts))
        let result = transition.vehicleConfirmationIntervalElapsed(from: state, conditions: F.conditions(now: F.referenceDate, isForeground: false))
        A.assertResult(result, state: state, effects: [.confirmVehicle(.adapterMaximum)])
    }

    /// 前面では、600回確認した後の待ち明けで、窓の内でも休止せず、その時刻から窓と回数(1)を取り直して確認を送ります。
    ///
    /// 責務: 回数上限の境界(600回目の後)を前面で確認します(U8 R6)。
    func testIntervalElapsedAfterAttemptLimitInForegroundRenewsWindow() {
        let now = F.referenceDate
        let state = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: F.maximumAttempts))
        let result = transition.vehicleConfirmationIntervalElapsed(from: state, conditions: F.conditions(now: now, isForeground: true))
        let renewed = F.confirmation(windowEndsAt: now.addingTimeInterval(F.windowSeconds), attemptCount: 1, phase: .probing)
        A.assertResult(result, state: .confirmingVehicle(renewed), effects: [.confirmVehicle(.adapterMaximum)])
    }

    /// 前面にいる間は、窓切れの後の待ち明けでも休止せず、窓を取り直して確認を送ります。
    ///
    /// 責務: `isForeground` の時に、窓の終了時刻ちょうどの待ち明けで窓が取り直され、アダプター最大タイムアウトの確認が出ることを確認します(U3 受け入れ条件 6)。
    func testIntervalElapsedAfterWindowEndWhileForegroundRenewsWindow() {
        let now = F.date(F.windowSeconds)
        let state = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: 4))
        let result = transition.vehicleConfirmationIntervalElapsed(from: state, conditions: F.conditions(now: now, isForeground: true))
        let renewed = F.confirmation(windowEndsAt: now.addingTimeInterval(F.windowSeconds), attemptCount: 1, phase: .probing)
        A.assertResult(result, state: .confirmingVehicle(renewed), effects: [.confirmVehicle(.adapterMaximum)])
    }

    /// 低頻度確認中以外で届いた待機終了は無視します。
    ///
    /// 責務: 休止中・待機・初期化中・検知済み・記録中・終了中で確認を要求しないことを確認します。
    func testIntervalElapsedOutsideProbingIsIgnored() {
        for state in F.allStates where state != .confirmingVehicle(F.confirmation(phase: .probing)) {
            A.assertIgnored(transition.vehicleConfirmationIntervalElapsed(from: state, conditions: F.conditions(now: F.date(1))), from: state, "\(state)")
        }
    }

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
