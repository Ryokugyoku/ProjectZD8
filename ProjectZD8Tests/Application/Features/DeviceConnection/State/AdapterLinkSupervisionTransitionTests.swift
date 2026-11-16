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
            (.recordingStartConfirmed(announcesStart: true), [recording]),
            (.recordingStartConfirmed(announcesStart: false), []),
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
                } else if isRecordingIntentCandidate(event, state) {
                    continue
                } else if handled.contains(state) {
                    XCTAssertTrue(result.state != state || !result.effects.isEmpty, "処理されなかった: \(state) / \(event)")
                } else {
                    A.assertIgnored(result, from: state, "\(state) / \(event)")
                }
            }
        }
    }

    /// 検知待ち以外で届いた[記録開始]のうち、「記録開始の意思」として扱われ得る組かどうかを返します。
    ///
    /// 責務: 待機・初期化中・確認中・VIN読取中の[記録開始]は、意思を状態の外に持つ実装もあり得るため、振り分けの網羅から外します。
    /// 記録中・終了処理中は従来どおり無視されるべきなので外しません(U4 受け入れ条件 5・9)。
    /// - Parameters:
    ///   - event: イベント。
    ///   - state: 状態。
    /// - Returns: 網羅の確認から外す組なら `true`。
    private func isRecordingIntentCandidate(_ event: AdapterLinkSupervisionEvent, _ state: AdapterLinkSupervisionState) -> Bool {
        guard case .recordingStartSelected = event else { return false }
        switch state {
        case .standby, .initializing, .confirmingVehicle: return true
        case let .vehicleDetected(_, phase): return phase == .readingVIN
        case .recording, .finishing, .heldAfterUserStop: return false
        }
    }

    /// 車両確認の失敗は無応答と同じく扱い、検知にせず、結果の受信を起点に次の確認へ進みます。
    ///
    /// 責務: 窓の中で最短間隔以上かかった失敗は次の確認、最短間隔より早い失敗は残り時間の待ち、背面での窓の終了時刻ちょうどは休止になることを確認します(U3 受け入れ条件 1・3・4)。
    func testVehicleConfirmationFailedBehavesAsNoResponse() {
        let probing = AdapterLinkSupervisionState.confirmingVehicle(F.confirmation())
        let now = F.date(10)
        let slow = transition.result(
            from: probing, on: .vehicleConfirmationFailed, conditions: F.conditions(now: now, lastVehicleConfirmationSentAt: F.date(5))
        )
        A.assertResult(slow, state: .confirmingVehicle(F.confirmation(attemptCount: 2)), effects: [.confirmVehicle(.adapterMaximum)])

        let quick = transition.result(from: probing, on: .vehicleConfirmationFailed, conditions: F.conditions(now: now, lastVehicleConfirmationSentAt: now))
        A.assertResult(quick, state: probing, effects: [.scheduleVehicleConfirmation(after: .seconds(1))])

        let atEnd = transition.result(from: probing, on: .vehicleConfirmationFailed, conditions: F.conditions(now: F.date(600)))
        A.assertResult(atEnd, state: .confirmingVehicle(F.confirmation(phase: .paused)), effects: [])
    }

    /// VIN読取の失敗でも検知は成立し、VINなしで通知または自動記録へ進みます。
    ///
    /// 責務: 自動記録オフはVINなしの検知通知、オンはVINなしの記録開始要求だけ(開始通知は確定後。U4 受け入れ条件 1)になることを確認します。
    func testVINReadFailedContinuesWithoutVIN() {
        let readingVIN = F.allStates[4]
        let vehicle = AdapterLinkDetectedVehicle(adapterProbeEvidence: F.evidence, vin: nil)
        let off = transition.result(from: readingVIN, on: .vinReadFailed(isAutomaticRecordingEnabled: false), conditions: F.conditions())
        A.assertResult(off, state: .vehicleDetected(vehicle, phase: .awaitingRecordingStart), effects: [.presentVehicleDetected(vin: nil)])

        let on = transition.result(from: readingVIN, on: .vinReadFailed(isAutomaticRecordingEnabled: true), conditions: F.conditions())
        A.assertResult(
            on,
            state: .recording(vehicle),
            effects: [.requestRecordingStart(F.expectedStartRequest(vin: nil))]
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

    /// 注入した時間定数が、確認窓・最短間隔・見張りの上限に使われます。
    ///
    /// 責務: 窓60秒・最短間隔10秒・見張り100秒の定数で、窓の終了時刻、最短間隔の残り時間の待ち、見張りの終わりの時刻がその値になることを確認します(U3 受け入れ条件 3・4・11)。
    func testInjectedTimingIsUsed() {
        let custom = AdapterLinkSupervisionTransition(
            timing: AdapterLinkSupervisionTiming(vehicleConfirmationWindow: 60, vehicleConfirmationInterval: 10, heldWatchLimit: 100)
        )
        let opened = custom.result(
            from: .initializing(linkReadyAt: F.referenceDate), on: .adapterInitializationSucceeded(F.evidence), conditions: F.conditions()
        )
        let confirmation = F.confirmation(windowEndsAt: F.date(60))
        XCTAssertEqual(opened.state, .confirmingVehicle(confirmation))

        let scheduled = custom.result(
            from: .confirmingVehicle(confirmation), on: .vehicleConfirmationCompleted(.noResponse),
            conditions: F.conditions(now: F.date(59), lastVehicleConfirmationSentAt: F.date(55))
        )
        A.assertResult(scheduled, state: .confirmingVehicle(confirmation), effects: [.scheduleVehicleConfirmation(after: .seconds(6))])

        let watching = custom.result(
            from: .heldAfterUserStop(.awaitingStart), on: .recordingEndSettled, conditions: F.conditions(now: F.date(7))
        )
        XCTAssertEqual(watching.state, F.watching(endsAt: F.date(107)))
    }

    /// サインアウトは記録中なら停止要求を出して終了へ、リンクを停止し通知を取り下げます。
    ///
    /// 責務: 稼働条件の変化が巻き戻しへ振り分けられることを代表の状態で確認します。
    func testSignOutWhileRecordingIsRoutedToTeardown() {
        let result = transition.result(
            from: .recording(F.detectedVehicle), on: .operatingConditionsChanged, conditions: F.conditions(isSignedIn: false)
        )
        A.assertResult(result, state: .finishing, effects: [.cancelOperations, .dismissNotification, .requestRecordingStop(.accountSignedOut), .stopLink])
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
