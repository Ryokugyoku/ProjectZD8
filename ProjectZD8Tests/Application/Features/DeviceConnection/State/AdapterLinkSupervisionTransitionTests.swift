import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionTransition.result(from:on:conditions:)` の全状態×全イベントの振り分けを検証します。
@MainActor
final class AdapterLinkSupervisionTransitionTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures
    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkSupervisionTransition()

    /// 全イベントと、既定条件(稼働中・リンク開始済み・直前 ready・窓の中)で処理される状態の組です。
    ///
    /// 責務: 仕様から、各イベントが状態を動かすか作用を出すべき状態を列挙します。ここにない状態では無視されるべきです。
    /// - Returns: イベントと処理される状態の組。
    private func eventsWithHandledStates() -> [(AdapterLinkSupervisionEvent, [AdapterLinkSupervisionState])] {
        let all = F.allStates
        let initializing = AdapterLinkSupervisionState.initializing(linkReadyAt: F.referenceDate)
        let probing = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(phase: .probing))
        let paused = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation(phase: .paused))
        let readingVIN = all[4]
        let awaiting = all[5]
        let recording = all[6]
        return [
            (.operatingConditionsChanged, []),
            (.linkStateChanged(.ready), []),
            (.linkStateChanged(.connecting), all),
            (.linkStateChanged(.disconnected(.peripheralDisconnected(errorDescription: nil))), all),
            (.adapterInitializationSucceeded(F.evidence), [initializing]),
            (.adapterInitializationFailed, [initializing]),
            (.vehicleConfirmationCompleted(.responding), [probing]),
            (.vehicleConfirmationCompleted(.noResponse), [probing]),
            (.vehicleConfirmationFailed, [probing]),
            (.vehicleConfirmationIntervalElapsed, [probing]),
            (.vinReadCompleted(vin: F.vin, isAutomaticRecordingEnabled: false), [readingVIN]),
            (.vinReadCompleted(vin: nil, isAutomaticRecordingEnabled: true), [readingVIN]),
            (.vinReadFailed(isAutomaticRecordingEnabled: false), [readingVIN]),
            (.vinReadFailed(isAutomaticRecordingEnabled: true), [readingVIN]),
            (.appDidBecomeActive, [.standby, paused]),
            (.recordingStartSelected, [awaiting]),
            (.recordingDidFinish(endReason: nil), [recording, .finishing]),
            (.finishingDidComplete, [.finishing]),
        ]
    }

    /// 全状態×全イベントで、処理されるべき組だけが結果を変え、それ以外は状態不変・作用なしです。
    ///
    /// 責務: 振り分けの漏れ(処理すべきイベントの無視)と過剰(無視すべきイベントの処理)を網羅的に確認します。
    /// 記録中のリンク断は、記録に無関係な後始末を出すかどうかを仕様が定めないため、記録を続けることだけを確認します(U2 受け入れ条件 1)。
    func testEveryStateAndEventIsHandledOrIgnoredAsSpecified() {
        let conditions = F.conditions(now: F.date(10))
        for (event, handled) in eventsWithHandledStates() {
            for state in F.allStates {
                let result = transition.result(from: state, on: event, conditions: conditions)
                if case .recording = state, case let .linkStateChanged(linkState) = event, linkState != .ready {
                    A.assertRecordingContinuesAfterLinkLoss(result, from: state, "\(event)")
                } else if handled.contains(state) {
                    XCTAssertTrue(result.state != state || !result.effects.isEmpty, "処理されなかった: \(state) / \(event)")
                } else {
                    A.assertIgnored(result, from: state, "\(state) / \(event)")
                }
            }
        }
    }

    /// 車両確認の失敗は無応答と同じく扱い、検知にせず再確認を予約します。
    ///
    /// 責務: 確認失敗が窓の中で30秒後の再確認になり、窓の終了時刻ちょうどでは休止になることを確認します。
    func testVehicleConfirmationFailedBehavesAsNoResponse() {
        let probing = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation())
        let inside = transition.result(from: probing, on: .vehicleConfirmationFailed, conditions: F.conditions(now: F.date(10)))
        A.assertResult(inside, state: probing, effects: [.scheduleVehicleConfirmation(after: .seconds(30))])

        let atEnd = transition.result(from: probing, on: .vehicleConfirmationFailed, conditions: F.conditions(now: F.date(600)))
        A.assertResult(atEnd, state: .confirmingVehicle(F.confirmation(phase: .paused)), effects: [])
    }

    /// VIN読取の失敗でも検知は成立し、VINなしで通知または自動記録へ進みます。
    ///
    /// 責務: 自動記録オフはVINなしの検知通知、オンはVINなしの記録開始要求と記録開始通知になることを確認します。
    func testVINReadFailedContinuesWithoutVIN() {
        let readingVIN = F.allStates[4]
        let vehicle = AdapterLinkDetectedVehicle(adapterProbeEvidence: F.evidence, vin: nil)
        let off = transition.result(from: readingVIN, on: .vinReadFailed(isAutomaticRecordingEnabled: false), conditions: F.conditions())
        A.assertResult(off, state: .vehicleDetected(vehicle, phase: .awaitingRecordingStart), effects: [.presentVehicleDetected(vin: nil)])

        let on = transition.result(from: readingVIN, on: .vinReadFailed(isAutomaticRecordingEnabled: true), conditions: F.conditions())
        A.assertResult(
            on,
            state: .recording(vehicle),
            effects: [.requestRecordingStart(F.expectedStartRequest(vin: nil)), .presentRecordingStarted(vin: nil)]
        )
    }

    /// 時刻は条件の `now` から取り、リンク `ready` の時刻を初期化中に記録します。
    ///
    /// 責務: 待機で `ready` が届いた時、条件の現在時刻が確認窓の起点になることを確認します。
    func testLinkReadyUsesConditionsNowAsWindowOrigin() {
        let now = F.date(77)
        let result = transition.result(
            from: .standby, on: .linkStateChanged(.ready), conditions: F.conditions(linkState: .discovering, now: now)
        )
        A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter])
    }

    /// 注入した時間定数が確認窓と再確認間隔に使われます。
    ///
    /// 責務: 窓60秒・間隔10秒の定数で、窓の終了時刻と待機時間がその値になることを確認します。
    func testInjectedTimingIsUsed() {
        let custom = AdapterLinkSupervisionTransition(
            timing: AdapterLinkSupervisionTiming(vehicleConfirmationWindow: 60, vehicleConfirmationInterval: 10)
        )
        let opened = custom.result(
            from: .initializing(linkReadyAt: F.referenceDate), on: .adapterInitializationSucceeded(F.evidence), conditions: F.conditions()
        )
        let confirmation = F.confirmation(windowEndsAt: F.date(60))
        XCTAssertEqual(opened.state, .confirmingVehicle(confirmation))

        let scheduled = custom.result(
            from: .confirmingVehicle(confirmation), on: .vehicleConfirmationCompleted(.noResponse), conditions: F.conditions(now: F.date(59))
        )
        A.assertResult(scheduled, state: .confirmingVehicle(confirmation), effects: [.scheduleVehicleConfirmation(after: .seconds(10))])
    }

    /// サインアウトは記録中なら停止要求を出して終了へ、リンクを停止し通知を取り下げます。
    ///
    /// 責務: 稼働条件の変化が巻き戻しへ振り分けられることを代表の状態で確認します。
    func testSignOutWhileRecordingIsRoutedToTeardown() {
        let result = transition.result(
            from: .recording(F.detectedVehicle), on: .operatingConditionsChanged, conditions: F.conditions(isSignedIn: false)
        )
        A.assertResult(result, state: .finishing, effects: [.cancelOperations, .dismissNotification, .requestRecordingStop, .stopLink])
    }

    /// 記録中のリンク断は、イベントの振り分けを経ても停止を要求せず記録中のままです。
    ///
    /// 責務: 切断理由の違うリンク断で、記録中のまま停止要求が出ないことを確認します(U2 受け入れ条件 1)。
    func testLinkLossWhileRecordingKeepsRecording() {
        let recording = AdapterLinkSupervisionState.recording(F.detectedVehicle)
        let lost: [AdapterLinkState] = [
            .disconnected(.peripheralDisconnected(errorDescription: nil)), .disconnected(.bluetoothPoweredOff), .connecting,
        ]
        for linkState in lost {
            let result = transition.result(from: recording, on: .linkStateChanged(linkState), conditions: F.conditions(linkState: .ready))
            A.assertRecordingContinuesAfterLinkLoss(result, from: recording, "\(linkState)")
        }
    }
}
