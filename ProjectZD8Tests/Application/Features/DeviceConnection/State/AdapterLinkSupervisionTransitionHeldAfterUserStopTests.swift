import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTransition` が、ユーザー切断後の抑止状態で、同じ走行が続く限り
/// 検知・記録開始をせず、走行の終わり(ECU の無応答が連続2回)・リンク断・稼働条件の変化で抑止を解くことを検証します。
///
/// 仕様: U3 受け入れ条件 8・10・11・12。見張りの確認の結果は `.vehicleConfirmationCompleted` で届く前提です。
@MainActor
final class AdapterLinkSupervisionTransitionHeldAfterUserStopTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkSupervisionTransition()

    /// 抑止中に前面へ戻っても、リンクが ready のままなら抑止のままで、検知も記録開始もしません(見張りの再開は出してよい)。
    ///
    /// 責務: 抑止のままで、初期化・VIN読取・通知・記録開始の作用が無いことを確認します(U3 受け入れ条件 8・11)。
    func testAppDidBecomeActiveKeepsHeldWithoutDetection() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        let result = transition.result(from: held, on: .appDidBecomeActive, conditions: F.conditions())
        assertStaysHeldWithoutDetection(result, "前面復帰")
    }

    /// 抑止中に見張りの確認で ECU の無応答を1回受けただけでは、抑止を解きません。
    ///
    /// 責務: 1回目の無応答で抑止のままで、検知・初期化の作用が無いことを確認します(U3 受け入れ条件 10)。
    func testSingleNoResponseWhileHeldKeepsHeld() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        let result = transition.result(from: held, on: .vehicleConfirmationCompleted(.noResponse), conditions: F.conditions())
        assertStaysHeldWithoutDetection(result, "無応答1回")
    }

    /// 抑止中に ECU の無応答を連続2回受けたら、走行が終わったとみなして抑止を解き、その時刻から初期化をやり直します。
    ///
    /// 責務: 2回目の無応答で `.initializing(linkReadyAt: 解いた時刻)` と初期化の作用になることを確認します(U3 受け入れ条件 10)。
    func testTwoConsecutiveNoResponsesWhileHeldRestartDetection() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        let first = transition.result(from: held, on: .vehicleConfirmationCompleted(.noResponse), conditions: F.conditions(now: F.date(5)))
        let now = F.date(7)
        let second = transition.result(from: first.state, on: .vehicleConfirmationCompleted(.noResponse), conditions: F.conditions(now: now))
        XCTAssertEqual(second.state, .initializing(linkReadyAt: now))
        XCTAssertTrue(second.effects.contains(.initializeAdapter))
    }

    /// 抑止中の無応答の間に ECU の応答があれば数え直し、その後の無応答1回では抑止を解きません。
    ///
    /// 責務: 無応答 → 応答 → 無応答 の並びで抑止のままであることを確認します(U3 受け入れ条件 8・10)。
    func testResponseBetweenNoResponsesResetsCount() {
        var state = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        for outcome in [VehicleResponseOutcome.noResponse, .responding, .noResponse] {
            let result = transition.result(from: state, on: .vehicleConfirmationCompleted(outcome), conditions: F.conditions())
            assertStaysHeldWithoutDetection(result, "\(outcome)")
            state = result.state
        }
    }

    /// 抑止中に ECU の応答(同じ走行が続いている)を受けても、検知も記録開始もせず抑止のままです。
    ///
    /// 責務: 応答ありの結果で抑止のままで、VIN読取・通知・記録開始の作用が無いことを確認します(U3 受け入れ条件 8)。
    func testRespondingWhileHeldKeepsHeldWithoutDetection() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        for event in [AdapterLinkSupervisionEvent.vehicleConfirmationCompleted(.responding), .vehicleConfirmationIntervalElapsed] {
            let result = transition.result(from: held, on: event, conditions: F.conditions())
            assertStaysHeldWithoutDetection(result, "\(event)")
        }
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

    /// 見張り中に手動接続が始まったら、抑止のままで、進行中の見張りの確認を取り消します(バイトストリームを取り合わない)。
    ///
    /// 責務: 抑止のまま(進行状況は変えない)で `.cancelOperations` が出て、見張りの確認を送らないことを確認します(決定 v)。
    func testExternalAdapterUseBeganCancelsWatchConfirmation() {
        let held = F.watching(noResponses: 1)
        let result = transition.result(from: held, on: .externalAdapterUseBegan, conditions: F.conditions(isExternalAdapterUseActive: true))
        XCTAssertEqual(result.state, held)
        XCTAssertTrue(result.effects.contains(.cancelOperations), "\(result.effects)")
        XCTAssertFalse(result.effects.contains(.confirmVehicle(.heldWatch)))
    }

    /// 手動接続が終わった時、まだ抑止中でリンクが `ready` なら、前面復帰を待たずに見張りを再開します(上限は保持に入った時点からのまま)。
    ///
    /// 責務: 見張りの終わりの時刻が変わらず、見張りの確認が出ることを確認します(決定 vi)。
    func testExternalAdapterUseEndedResumesWatchWithSameLimit() {
        let held = F.watching(noResponses: 0, endsAt: F.date(F.heldWatchSeconds))
        let result = transition.result(from: held, on: .externalAdapterUseEnded, conditions: F.conditions(now: F.date(120)))
        XCTAssertEqual(result.state, held)
        XCTAssertTrue(result.effects.contains(.confirmVehicle(.heldWatch)), "\(result.effects)")
    }

    /// 手動接続が終わった時にリンクが `ready` でなければ、見張りを再開しません。
    ///
    /// 責務: 抑止のままで、見張りの確認が出ないことを確認します(決定 vi)。
    func testExternalAdapterUseEndedWithoutReadyLinkDoesNotResume() {
        let held = F.watching()
        let result = transition.result(from: held, on: .externalAdapterUseEnded, conditions: F.conditions(linkState: .connecting))
        XCTAssertTrue(result.state.isHeldAfterUserStop)
        XCTAssertFalse(result.effects.contains(.confirmVehicle(.heldWatch)))
    }

    /// 見張りの開始待ちで手動接続が始まっても、抑止はそのままで、作用を出しません。
    ///
    /// 責務: `.heldAfterUserStop(.awaitingStart)` で `externalAdapterUseBegan` を受けた時に、状態不変・作用なし
    /// (見張りの確認はまだ送っていないので取り消すものが無い)であることを確認します。
    func testExternalAdapterUseBeganBeforeWatchStartKeepsHeldWithoutEffects() {
        let held = AdapterLinkSupervisionState.heldAfterUserStop(.awaitingStart)
        let result = transition.result(from: held, on: .externalAdapterUseBegan, conditions: F.conditions(isExternalAdapterUseActive: true))
        A.assertIgnored(result, from: held)
    }

    /// 見張りの開始待ちで手動接続が終わり、リンクが `ready` なら、その時刻から見張りを始めます。
    ///
    /// 責務: `.heldAfterUserStop(.awaitingStart)` で `externalAdapterUseEnded` を受けると、終わりの時刻=受けた時刻+上限の見張り中になり、
    /// 見張りの確認が1件出ることを確認します(U8 R5)。
    func testExternalAdapterUseEndedBeforeWatchStartStartsWatchWhenLinkReady() {
        let held = AdapterLinkSupervisionState.heldAfterUserStop(.awaitingStart)
        let now = F.date(30)
        let result = transition.result(from: held, on: .externalAdapterUseEnded, conditions: F.conditions(now: now))
        A.assertResult(
            result, state: F.watching(noResponses: 0, endsAt: now.addingTimeInterval(F.heldWatchSeconds)), effects: [.confirmVehicle(.heldWatch)]
        )
    }

    /// 見張りの開始待ちで手動接続が終わっても、リンクが `ready` でなければ見張りを始めません。
    ///
    /// 責務: リンクが接続中の時は状態不変・作用なしであることを確認します(U8 R5 の条件)。
    func testExternalAdapterUseEndedBeforeWatchStartWithoutReadyLinkDoesNothing() {
        let held = AdapterLinkSupervisionState.heldAfterUserStop(.awaitingStart)
        let result = transition.result(from: held, on: .externalAdapterUseEnded, conditions: F.conditions(linkState: .connecting))
        A.assertIgnored(result, from: held)
    }

    /// 抑止中は、記録開始選択・初期化・VIN読取・終了完了のイベントを無視します。
    ///
    /// 責務: それぞれのイベントで状態不変・作用なしを確認します。
    /// 見張りの確認の結果(応答・無応答・待機明け)は、見張りの検証(U3 受け入れ条件 9〜11)で扱うためここには含めません。
    func testOtherEventsAreIgnoredWhileHeld() {
        let held = AdapterLinkSupervisionHeldStateFixture.heldAfterUserStop()
        let events: [AdapterLinkSupervisionEvent] = [
            .recordingStartSelected,
            .adapterInitializationSucceeded(F.evidence),
            .adapterInitializationFailed,
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

    /// 抑止のままで、検知・記録開始につながる作用が無いことを検証します。
    ///
    /// 責務: 次の状態が抑止の種類のままで、初期化・VIN読取・検知通知・記録開始通知・記録開始・リンクの開始停止を含まないことを確認します。
    /// 見張りの確認(`confirmVehicle` など)は出してよいとします。
    /// - Parameters:
    ///   - result: 検証する遷移結果。
    ///   - message: 失敗時の補足。
    private func assertStaysHeldWithoutDetection(
        _ result: AdapterLinkSupervisionTransitionResult,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .heldAfterUserStop = result.state {} else {
            XCTFail("抑止のままではない: \(result.state) \(message)", file: file, line: line)
        }
        for effect in result.effects {
            switch effect {
            case .initializeAdapter, .readVIN, .presentVehicleDetected, .presentRecordingStarted, .requestRecordingStart, .stopLink, .startLink:
                XCTFail("出してはいけない作用 \(effect): \(message)", file: file, line: line)
            default:
                continue
            }
        }
    }
}
