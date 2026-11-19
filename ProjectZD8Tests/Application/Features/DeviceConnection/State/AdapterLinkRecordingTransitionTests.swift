import XCTest
@testable import ProjectZD8

/// `AdapterLinkRecordingTransition` の検知通知・自動/手動の記録開始・記録終了を、全状態について検証します。
@MainActor
final class AdapterLinkRecordingTransitionTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures
    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkRecordingTransition()

    /// VIN読取中の検知済み状態です。
    private var readingVIN: AdapterLinkSupervisionState {
        .vehicleDetected(AdapterLinkDetectedVehicle(adapterProbeEvidence: F.evidence, vin: nil), phase: .readingVIN)
    }

    /// 記録開始操作待ちの検知済み状態です。
    private var awaitingStart: AdapterLinkSupervisionState {
        .vehicleDetected(F.detectedVehicle, phase: .awaitingRecordingStart)
    }

    /// 自動記録オフなら、読み取ったVIN付きの「車両を検知しました」通知を1回提示し、記録は始めません。
    ///
    /// 責務: VINあり・なしの両方で、操作待ちへ移り通知1件だけが出ることを確認します。
    func testVINReadWithAutomaticRecordingOffPresentsDetectionOnce() {
        for vin in [F.vin, nil] {
            let result = transition.vinReadFinished(vin: vin, isAutomaticRecordingEnabled: false, from: readingVIN, conditions: F.conditions())
            let vehicle = AdapterLinkDetectedVehicle(adapterProbeEvidence: F.evidence, vin: vin)
            A.assertResult(
                result,
                state: .vehicleDetected(vehicle, phase: .awaitingRecordingStart),
                effects: [.presentVehicleDetected(vin: vin)],
                "\(String(describing: vin))"
            )
        }
    }

    /// 自動記録オンなら、操作なしで記録開始を要求して記録中へ移ります。「記録を開始しました」通知は、記録開始が確定するまで出しません。
    ///
    /// 責務: 作用が記録開始要求だけ(接続終端・VIN・判定結果が仕様どおり)で、開始通知を含まないことをVINあり・なしで確認します(U4 受け入れ条件 1・2)。
    func testVINReadWithAutomaticRecordingOnStartsRecording() {
        for vin in [F.vin, nil] {
            let result = transition.vinReadFinished(vin: vin, isAutomaticRecordingEnabled: true, from: readingVIN, conditions: F.conditions())
            let vehicle = AdapterLinkDetectedVehicle(adapterProbeEvidence: F.evidence, vin: vin)
            A.assertResult(
                result,
                state: .recording(vehicle),
                effects: [.requestRecordingStart(F.expectedStartRequest(vin: vin))],
                "\(String(describing: vin))"
            )
        }
    }

    /// 自動記録の記録開始要求の接続終端は、リンクを開始した接続対象から作ります。
    ///
    /// 責務: 保存済み既定と開始済みリンクの対象が異なる場合、リンクの対象が使われることを確認します。
    func testAutomaticRecordingUsesLinkPreferenceForEndpoint() {
        let conditions = F.conditions(defaultAdapterPreference: F.otherBLEPreference, linkPreference: F.blePreference)
        let result = transition.vinReadFinished(vin: F.vin, isAutomaticRecordingEnabled: true, from: readingVIN, conditions: conditions)
        XCTAssertTrue(result.effects.contains(.requestRecordingStart(F.expectedStartRequest(preference: F.blePreference, vin: F.vin))))
    }

    /// リンクの接続対象がない時は、自動記録オンでも記録開始を要求しません。
    ///
    /// 責務: 接続終端を作れない条件で記録開始要求も記録中への遷移も起きないことを確認します。
    func testAutomaticRecordingWithoutLinkPreferenceDoesNotStartRecording() {
        let result = transition.vinReadFinished(
            vin: F.vin, isAutomaticRecordingEnabled: true, from: readingVIN, conditions: F.conditions(linkPreference: nil)
        )
        XCTAssertFalse(result.effects.contains { if case .requestRecordingStart = $0 { true } else { false } })
        if case .recording = result.state { XCTFail("記録中へ移った: \(result.state)") }
    }

    /// VIN読取中以外で届いたVIN読取結果は無視します(通知の二重提示・記録の二重開始を防ぐ)。
    ///
    /// 責務: 操作待ち・記録中・その他の全状態で、自動記録オン・オフとも状態も作用も変えないことを確認します。
    func testVINReadOutsideReadingVINIsIgnored() {
        for state in F.allStates where state != readingVIN {
            for isEnabled in [false, true] {
                let result = transition.vinReadFinished(
                    vin: F.vin, isAutomaticRecordingEnabled: isEnabled, from: state, conditions: F.conditions()
                )
                A.assertIgnored(result, from: state, "\(state) auto=\(isEnabled)")
            }
        }
    }

    /// 有効期限内の記録開始の意思があれば、自動記録オフでも検知通知を出さずに記録開始を要求して記録中へ移ります。
    ///
    /// 責務: VINあり・なしの両方で、作用が記録開始要求だけ(検知通知・開始通知なし)であることを確認します(U4 受け入れ条件 6)。
    func testVINReadWithValidIntentStartsRecordingEvenWhenAutomaticRecordingIsOff() {
        for vin in [F.vin, nil] {
            let result = transition.vinReadFinished(
                vin: vin, isAutomaticRecordingEnabled: false, from: readingVIN, conditions: F.conditions(hasValidRecordingIntent: true)
            )
            let vehicle = AdapterLinkDetectedVehicle(adapterProbeEvidence: F.evidence, vin: vin)
            A.assertResult(
                result,
                state: .recording(vehicle),
                effects: [.requestRecordingStart(F.expectedStartRequest(vin: vin))],
                "\(String(describing: vin))"
            )
        }
    }

    /// 意思があってもリンクの接続対象が無ければ、記録開始を要求しません。
    ///
    /// 責務: 接続終端を作れない条件では、意思があっても記録中へ移らないことを確認します。
    func testVINReadWithValidIntentWithoutLinkPreferenceDoesNotStartRecording() {
        let result = transition.vinReadFinished(
            vin: F.vin,
            isAutomaticRecordingEnabled: false,
            from: readingVIN,
            conditions: F.conditions(linkPreference: nil, hasValidRecordingIntent: true)
        )
        XCTAssertFalse(result.effects.contains { if case .requestRecordingStart = $0 { true } else { false } })
        if case .recording = result.state { XCTFail("記録中へ移った: \(result.state)") }
    }

    /// 記録中に開始の確定が届き、自動記録で始めた記録なら、検知した車両のVINで「記録を開始しました」を出します。状態は変えません。
    ///
    /// 責務: VINあり・なしの記録中で、作用が開始通知1件だけで記録中のままであることを確認します(U4 受け入れ条件 1)。
    func testRecordingStartConfirmedWhileRecordingAnnouncesStart() {
        for vin in [F.vin, nil] {
            let recording = AdapterLinkSupervisionState.recording(AdapterLinkDetectedVehicle(adapterProbeEvidence: F.evidence, vin: vin))
            let result = transition.recordingStartConfirmed(announcesStart: true, from: recording)
            A.assertResult(result, state: recording, effects: [.presentRecordingStarted(vin: vin)], "\(String(describing: vin))")
        }
    }

    /// 通知すべきでない記録(手動・意思で始めた記録)の確定では、記録中でも何も出しません。
    ///
    /// 責務: `announcesStart` が偽なら状態も作用も変えないことを確認します(U4 受け入れ条件 4)。
    func testRecordingStartConfirmedWithoutAnnouncementIsIgnored() {
        let recording = AdapterLinkSupervisionState.recording(F.detectedVehicle)
        A.assertIgnored(transition.recordingStartConfirmed(announcesStart: false, from: recording), from: recording)
    }

    /// 記録中以外(既に終わった・別の段階)に届いた確定は、古い結果として無視します。
    ///
    /// 責務: 記録中以外の全状態と抑止中で、`announcesStart` が真でも状態も作用も変えないことを確認します(U4 受け入れ条件 3)。
    func testRecordingStartConfirmedOutsideRecordingIsIgnored() {
        let states = F.allStates.filter { if case .recording = $0 { false } else { true } } + [.heldAfterUserStop(.awaitingStart), F.watching()]
        for state in states {
            for announces in [true, false] {
                A.assertIgnored(transition.recordingStartConfirmed(announcesStart: announces, from: state), from: state, "\(state) \(announces)")
            }
        }
    }

    /// [記録開始]の選択で、検知通知を取り下げ、記録開始を要求して記録中へ移ります。記録開始通知は出しません。
    ///
    /// 責務: 手動開始の作用が「取り下げ」と「接続終端・VIN・判定結果付きの開始要求」だけであることを確認します。
    func testRecordingStartSelectedWhileAwaitingStartsRecording() {
        let result = transition.recordingStartSelected(from: awaitingStart, conditions: F.conditions())
        A.assertResult(
            result,
            state: .recording(F.detectedVehicle),
            effects: [.dismissNotification, .requestRecordingStart(F.expectedStartRequest(vin: F.vin))]
        )
    }

    /// 記録中・終了処理中・ユーザー切断後の抑止中に届いた[記録開始]は無視します。
    ///
    /// 責務: これらの状態で状態も作用も変えないことを確認します(U4 受け入れ条件 9)。
    /// 待機・初期化中・確認中・VIN読取中に届いた選択は「記録開始の意思」として扱うため(受け入れ条件 5〜7)、ここには含めません。
    func testRecordingStartSelectedWhileRecordingFinishingOrHeldIsIgnored() {
        let states: [AdapterLinkSupervisionState] = [.recording(F.detectedVehicle), .finishing, .heldAfterUserStop(.awaitingStart), F.watching()]
        for state in states {
            A.assertIgnored(transition.recordingStartSelected(from: state, conditions: F.conditions()), from: state, "\(state)")
        }
    }

    /// リンクの接続対象がない時の[記録開始]は記録開始を要求しません。
    ///
    /// 責務: 接続終端を作れない条件で記録開始要求も記録中への遷移も起きないことを確認します。
    func testRecordingStartSelectedWithoutLinkPreferenceDoesNotStart() {
        let result = transition.recordingStartSelected(from: awaitingStart, conditions: F.conditions(linkPreference: nil))
        XCTAssertFalse(result.effects.contains { if case .requestRecordingStart = $0 { true } else { false } })
        if case .recording = result.state { XCTFail("記録中へ移った: \(result.state)") }
    }

    /// リンクが `ready` でない時に、記録中の記録終了(終了理由なし)が通知されたら終了へ進み、終了を完了させる作用を出し、
    /// その作用の結果として待機に落ち着きます(再確認の待ちは予約しません)。
    ///
    /// 責務: リンクが `ready` でない・リンク未開始の各条件で、遷移結果が「終了中・作用は通知の取り下げと終了の完了だけ
    /// (停止要求・待ちの予約なし)」の1通りで、続く終了の完了で作用なしに待機へ戻ることを確認します(S1-3 の「ready でなければ従来どおり待機」)。
    /// リンクが `ready` の場合の待ちを挟んだ再確認は `AdapterLinkSupervisionTransitionDeclinedRecordingRetryTests` が扱います。
    func testRecordingDidFinishWhileRecordingWithoutReadyLinkSettlesToStandby() {
        for conditions in [F.conditions(linkState: .connecting), F.conditions(linkPreference: nil)] {
            let result = transition.recordingDidFinish(endReason: nil, from: .recording(F.detectedVehicle), conditions: conditions)
            A.assertResult(result, state: .finishing, effects: [.dismissNotification, .completeFinishing], "\(conditions)")

            A.assertResult(transition.finishingDidComplete(from: result.state), state: .standby, effects: [], "\(conditions)")
        }
    }

    /// 終了中(リンク断で停止要求済み)に記録終了が通知されたら待機へ戻ります。
    ///
    /// 責務: 停止要求を重ねずに `standby` へ戻ることを確認します。
    func testRecordingDidFinishWhileFinishingReturnsToStandby() {
        A.assertResult(transition.recordingDidFinish(endReason: nil, from: .finishing, conditions: F.conditions()), state: .standby, effects: [])
    }

    /// 記録中・終了中以外で届いた記録終了は無視します。
    ///
    /// 責務: 待機・初期化中・確認中・検知済みで状態も作用も変えないことを確認します。
    func testRecordingDidFinishInOtherStatesIsIgnored() {
        for state in F.allStates {
            if case .recording = state { continue }
            if state == .finishing { continue }
            A.assertIgnored(transition.recordingDidFinish(endReason: nil, from: state, conditions: F.conditions()), from: state, "\(state)")
        }
    }

    /// 終了処理の完了は、終了中なら待機へ戻し、それ以外では無視します。
    ///
    /// 責務: `finishingDidComplete(from:)` の分岐を全状態で確認します。
    func testFinishingDidCompleteForEveryState() {
        for state in F.allStates {
            let result = transition.finishingDidComplete(from: state)
            if state == .finishing {
                A.assertResult(result, state: .standby, effects: [])
            } else {
                A.assertIgnored(result, from: state, "\(state)")
            }
        }
    }
}
