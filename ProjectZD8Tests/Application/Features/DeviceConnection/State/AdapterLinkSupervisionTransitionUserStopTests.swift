import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTransition` が、記録中のユーザー切断を抑止状態へ移し、
/// それ以外の終了理由・終了中の通知は従来どおりに扱うことを検証します。
@MainActor
final class AdapterLinkSupervisionTransitionUserStopTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkSupervisionTransition()

    /// 記録中にユーザー切断で終了すると、待機でも終了中でもない抑止状態へ移り、通知を取り下げるだけです。
    ///
    /// 責務: 作用が `[.dismissNotification]` のみで、終了処理の完了を含まないことを確認します。
    func testUserDisconnectWhileRecordingEntersHeldStateWithoutCompletingFinishing() {
        let result = transition.result(
            from: .recording(F.detectedVehicle),
            on: .recordingDidFinish(endReason: .userDisconnected),
            conditions: F.conditions()
        )
        XCTAssertEqual(result.state, .heldAfterUserStop)
        XCTAssertEqual(result.effects, [.dismissNotification])
        XCTAssertFalse(result.effects.contains(.completeFinishing))
    }

    /// ユーザー切断以外の終了理由(と理由なし)で記録が終わった時は、従来どおり終了中へ移ります。
    ///
    /// 責務: 理由ごとに `.finishing` と `[.dismissNotification, .completeFinishing]` になることを確認します。
    func testOtherEndReasonsWhileRecordingStillFinish() {
        let reasons: [ConnectionSessionEndReason?] = [
            .vehicleNoResponse, .connectionLost, .acquisitionFailed, .superseded, .accountSignedOut, nil,
        ]
        for reason in reasons {
            let result = transition.result(
                from: .recording(F.detectedVehicle),
                on: .recordingDidFinish(endReason: reason),
                conditions: F.conditions()
            )
            A.assertResult(result, state: .finishing, effects: [.dismissNotification, .completeFinishing], "\(String(describing: reason))")
        }
    }

    /// 終了中にユーザー切断の終了通知を受けた時(リンク断で監視自身が止めた場合)は、従来どおり待機へ戻ります。
    ///
    /// 責務: 終了中の `.userDisconnected` が抑止せず `.standby`・作用なしになることを確認します。
    func testUserDisconnectWhileFinishingReturnsToStandby() {
        let result = transition.result(
            from: .finishing,
            on: .recordingDidFinish(endReason: .userDisconnected),
            conditions: F.conditions(linkState: .connecting)
        )
        A.assertResult(result, state: .standby, effects: [])
    }

    /// 終了中から待機へ戻った後、前面復帰すれば従来どおり初期化からやり直します。
    ///
    /// 責務: 抑止していない場合に、前面復帰が初期化を始めることを確認します。
    func testForegroundAfterFinishingUserDisconnectInitializes() {
        let standby = transition.result(
            from: .finishing,
            on: .recordingDidFinish(endReason: .userDisconnected),
            conditions: F.conditions()
        ).state
        XCTAssertEqual(standby, .standby)
        let result = transition.result(from: standby, on: .appDidBecomeActive, conditions: F.conditions())
        A.assertResult(result, state: .initializing(linkReadyAt: F.referenceDate), effects: [.initializeAdapter])
    }

    /// リンクが `ready` でない(リンク断で一時停止中など)記録中にユーザー切断で終わった時は、抑止せず待機へ戻ります。
    ///
    /// 責務: 保持すべき「同じ接続」が無い場合に `heldAfterUserStop` へ移らず、待機(または待機へ戻る終了処理)になることを確認します(U2 受け入れ条件 8)。
    func testUserDisconnectWhileRecordingWithoutReadyLinkReturnsToStandby() {
        let nonReady: [AdapterLinkState] = [
            .connecting, .discovering, .awaitingPeripheral, .disconnected(.peripheralDisconnected(errorDescription: nil)),
        ]
        for linkState in nonReady {
            let result = transition.result(
                from: .recording(F.detectedVehicle),
                on: .recordingDidFinish(endReason: .userDisconnected),
                conditions: F.conditions(linkState: linkState)
            )
            XCTAssertNotEqual(result.state, .heldAfterUserStop, "\(linkState)")
            XCTAssertFalse(AdapterLinkSupervisionResultAssertions.containsRecordingStopRequest(result.effects), "\(linkState)")
            if result.state == .finishing {
                XCTAssertTrue(result.effects.contains(.completeFinishing), "終了中なら待機へ戻る: \(linkState)")
            } else {
                XCTAssertEqual(result.state, .standby, "\(linkState)")
            }
        }
    }

    /// リンクが `ready` でない記録中に、ユーザー切断以外の理由で終わった時は、従来どおり終了中を経て待機へ戻ります。
    ///
    /// 責務: 猶予切れ(接続断)などの終了で、抑止せず `.finishing` と `[.dismissNotification, .completeFinishing]` になることを確認します(U2 受け入れ条件 3)。
    func testOtherEndReasonsWhileRecordingWithoutReadyLinkStillFinish() {
        let reasons: [ConnectionSessionEndReason?] = [.connectionLost, .vehicleNoResponse, .acquisitionFailed, nil]
        for reason in reasons {
            let result = transition.result(
                from: .recording(F.detectedVehicle),
                on: .recordingDidFinish(endReason: reason),
                conditions: F.conditions(linkState: .disconnected(.peripheralDisconnected(errorDescription: nil)))
            )
            A.assertResult(result, state: .finishing, effects: [.dismissNotification, .completeFinishing], "\(String(describing: reason))")
        }
    }

    /// 記録中以外の状態でユーザー切断の終了通知を受けても、抑止状態へは移りません。
    ///
    /// 責務: 待機・初期化中・確認中・検知済みでは状態も作用も変わらないことを確認します。
    func testUserDisconnectOutsideRecordingIsIgnored() {
        let states = F.allStates.filter { state in
            if case .recording = state { return false }
            return state != .finishing
        }
        XCTAssertEqual(states.count, 6)
        for state in states {
            let result = transition.result(from: state, on: .recordingDidFinish(endReason: .userDisconnected), conditions: F.conditions())
            A.assertIgnored(result, from: state, "\(state)")
        }
    }
}
