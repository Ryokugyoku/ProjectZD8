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
    /// 責務: 初期化中から作用なしで `standby` へ戻ることを確認します。
    func testInitializationFailedReturnsToStandbyWithoutEffects() {
        let result = transition.adapterInitializationFailed(from: .initializing(linkReadyAt: F.referenceDate))
        A.assertResult(result, state: .standby, effects: [])
    }

    /// 初期化中以外で届いた初期化失敗は無視します。
    ///
    /// 責務: 確認中や検知済みへ古い失敗が届いても待機へ巻き戻さないことを確認します。
    func testInitializationFailedOutsideInitializingIsIgnored() {
        for state in F.allStates {
            if case .initializing = state { continue }
            A.assertIgnored(transition.adapterInitializationFailed(from: state), from: state, "\(state)")
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

    /// 窓の中で無応答なら、状態を保ったまま30秒後の再確認を予約します。リンクは止めません。
    ///
    /// 責務: 窓の開始直後と終了直前(1ミリ秒前)で再確認の予約だけが出ることを確認します。
    func testNoResponseInsideWindowSchedulesRecheckAfterInterval() {
        let state = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: 1))
        for now in [F.date(0), F.date(F.windowSeconds - 0.001)] {
            let result = transition.vehicleConfirmationCompleted(.noResponse, from: state, conditions: F.conditions(now: now))
            A.assertResult(result, state: state, effects: [.scheduleVehicleConfirmation(after: .seconds(30))], "\(now)")
        }
    }

    /// 窓の終了時刻ちょうど・それ以降の無応答では確認をやめて休止します。
    ///
    /// 責務: 10分ちょうど・10分+1ミリ秒で、作用なしで `paused` へ移ることを確認します。
    func testNoResponseAtOrAfterWindowEndPauses() {
        let confirmation = F.confirmation(attemptCount: 3)
        for now in [F.date(F.windowSeconds), F.date(F.windowSeconds + 0.001)] {
            let result = transition.vehicleConfirmationCompleted(.noResponse, from: .confirmingVehicle(confirmation), conditions: F.conditions(now: now))
            A.assertResult(result, state: .confirmingVehicle(F.confirmation(attemptCount: 3, phase: .paused)), effects: [], "\(now)")
        }
    }

    /// 時計が進まなくても、20回目の確認が無応答なら休止し、21回目を予約しません。
    ///
    /// 責務: 19回目の無応答は予約、20回目の無応答は休止という回数の境界を確認します。
    func testNoResponseHonorsAttemptLimitWithFrozenClock() {
        let nineteenth = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: F.maximumAttempts - 1))
        let scheduled = transition.vehicleConfirmationCompleted(.noResponse, from: nineteenth, conditions: F.conditions(now: F.referenceDate))
        A.assertResult(scheduled, state: nineteenth, effects: [.scheduleVehicleConfirmation(after: .seconds(30))])

        let twentieth = F.confirmation(attemptCount: F.maximumAttempts)
        let paused = transition.vehicleConfirmationCompleted(.noResponse, from: .confirmingVehicle(twentieth), conditions: F.conditions(now: F.referenceDate))
        let expected = F.confirmation(attemptCount: F.maximumAttempts, phase: .paused)
        A.assertResult(paused, state: .confirmingVehicle(expected), effects: [])
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

    /// 待機が終わった時点で窓を過ぎていれば、確認せずに休止します。
    ///
    /// 責務: 10分ちょうど・それ以降で確認を要求せず `paused` へ移ることを確認します。
    func testIntervalElapsedAtOrAfterWindowEndPauses() {
        for now in [F.date(F.windowSeconds), F.date(F.windowSeconds + 30)] {
            let result = transition.vehicleConfirmationIntervalElapsed(
                from: .confirmingVehicle(F.confirmation(attemptCount: 4)), conditions: F.conditions(now: now)
            )
            A.assertResult(result, state: .confirmingVehicle(F.confirmation(attemptCount: 4, phase: .paused)), effects: [], "\(now)")
        }
    }

    /// 20回確認した後の待機終了では、時計が進んでいなくても21回目を要求せず休止します。
    ///
    /// 責務: 回数上限の境界(20回目の後)を確認します。
    func testIntervalElapsedAfterTwentiethAttemptPauses() {
        let state = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(attemptCount: F.maximumAttempts))
        let result = transition.vehicleConfirmationIntervalElapsed(from: state, conditions: F.conditions(now: F.referenceDate))
        A.assertResult(result, state: .confirmingVehicle(F.confirmation(attemptCount: F.maximumAttempts, phase: .paused)), effects: [])
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
