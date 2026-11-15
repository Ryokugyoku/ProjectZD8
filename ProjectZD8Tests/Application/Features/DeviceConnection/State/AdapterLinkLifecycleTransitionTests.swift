import XCTest
@testable import ProjectZD8

/// `AdapterLinkLifecycleTransition` の稼働条件・リンク状態の変化と巻き戻しを、仕様の全状態について検証します。
@MainActor
final class AdapterLinkLifecycleTransitionTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures
    /// 遷移結果の検証手段です。
    private typealias A = AdapterLinkSupervisionResultAssertions

    /// 検証対象の遷移です。
    private let transition = AdapterLinkLifecycleTransition()

    /// `ready` 以外の全てのリンク状態です。
    private let nonReadyLinkStates: [AdapterLinkState] = [
        .idle, .awaitingPeripheral, .connecting, .discovering,
        .disconnected(.peripheralDisconnected(errorDescription: "lost")), .disconnected(.retryLimitExceeded),
    ]

    /// 仕様の「稼働条件が崩れた・接続対象が変わった」時の、状態ごとの巻き戻し先と作用です(リンク停止は含まない)。
    ///
    /// 責務: 記録中は停止要求を出して終了へ、終了中は終了のまま、それ以外は待機へ戻り、どの状態でも進行中の処理を取り消して通知を取り下げる期待値を返します。
    /// リンク断の期待値は `expectedLinkLossTeardown(from:)` で、記録中の扱いが異なります(U2 受け入れ条件 1・9〜11)。
    /// - Parameter state: 巻き戻す前の状態。
    /// - Returns: 期待する次の状態と作用。
    private func expectedConditionsLostTeardown(
        from state: AdapterLinkSupervisionState
    ) -> (state: AdapterLinkSupervisionState, effects: [AdapterLinkSupervisionEffect]) {
        switch state {
        case .recording: (.finishing, [.cancelOperations, .dismissNotification, .requestRecordingStop])
        case .finishing: (.finishing, [.cancelOperations, .dismissNotification])
        default: (.standby, [.cancelOperations, .dismissNotification])
        }
    }

    /// 仕様の「リンクが切れた」時の、記録中以外の状態ごとの巻き戻し先と作用です(リンク停止は含まない)。
    ///
    /// 責務: 終了中は終了のまま、それ以外は待機へ戻り、進行中の処理を取り消して通知を取り下げる期待値を返します。
    /// 記録中は停止を要求せず記録中のまま(U2 受け入れ条件 1)で、`assertRecordingContinuesAfterLinkLoss` で検証するため `nil` を返します。
    /// - Parameter state: 巻き戻す前の状態。
    /// - Returns: 期待する次の状態と作用。記録中は `nil`。
    private func expectedLinkLossTeardown(
        from state: AdapterLinkSupervisionState
    ) -> (state: AdapterLinkSupervisionState, effects: [AdapterLinkSupervisionEffect])? {
        switch state {
        case .recording: nil
        case .finishing: (.finishing, [.cancelOperations, .dismissNotification])
        default: (.standby, [.cancelOperations, .dismissNotification])
        }
    }

    /// リンク断の結果を、記録中かどうかで分けて検証します。
    ///
    /// 責務: 記録中は記録を続けること、それ以外は期待どおりに巻き戻すことを確認します。
    /// - Parameters:
    ///   - result: 検証する遷移結果。
    ///   - state: 巻き戻す前の状態。
    ///   - message: 失敗時に添える説明。
    private func assertLinkLossResult(
        _ result: AdapterLinkSupervisionTransitionResult,
        from state: AdapterLinkSupervisionState,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let expected = expectedLinkLossTeardown(from: state) else {
            A.assertRecordingContinuesAfterLinkLoss(result, from: state, message, file: file, line: line)
            return
        }
        A.assertResult(result, state: expected.state, effects: expected.effects, message, file: file, line: line)
    }

    /// 稼働条件を満たさず、リンクも未開始なら何もしません。
    ///
    /// 責務: 未開始・未サインイン・既定なし・Classic・シリアルで待機のままリンクを開始しないことを確認します。
    func testOperatingConditionsWithoutTargetAndWithoutLinkAreIgnored() {
        let variants: [AdapterLinkSupervisionConditions] = [
            F.conditions(isSupervisionStarted: false, linkPreference: nil, linkState: .idle),
            F.conditions(isSignedIn: false, linkPreference: nil, linkState: .idle),
            F.conditions(defaultAdapterPreference: nil, linkPreference: nil, linkState: .idle),
            F.conditions(defaultAdapterPreference: F.classicPreference, linkPreference: nil, linkState: .idle),
            F.conditions(defaultAdapterPreference: F.serialPreference, linkPreference: nil, linkState: .idle),
        ]
        for conditions in variants {
            A.assertIgnored(transition.operatingConditionsChanged(from: .standby, conditions: conditions), from: .standby)
        }
    }

    /// 稼働条件を満たしリンク未開始なら、状態を変えずに既定アダプターでリンクを開始します。
    ///
    /// 責務: 待機と終了中のそれぞれで `startLink` だけが出て、停止も通知もしないことを確認します。
    func testOperatingConditionsWithTargetStartLinkWhenNotStarted() {
        let conditions = F.conditions(linkPreference: nil, linkState: .idle)
        for state: AdapterLinkSupervisionState in [.standby, .finishing] {
            let result = transition.operatingConditionsChanged(from: state, conditions: conditions)
            A.assertResult(result, state: state, effects: [.prepareNotifications, .startLink(F.blePreference)], "\(state)")
        }
    }

    /// 接続対象が開始済みリンクと同じなら、全状態で何もしません(二重開始の防止)。
    ///
    /// 責務: `start()` の重複・同じ状態の再通知でリンク開始・停止・通知が走らないことを全状態で確認します。
    func testOperatingConditionsWithUnchangedTargetAreIgnoredInEveryState() {
        for state in F.allStates {
            for linkState in [AdapterLinkState.ready, .connecting] {
                let result = transition.operatingConditionsChanged(from: state, conditions: F.conditions(linkState: linkState))
                A.assertIgnored(result, from: state, "\(state) \(linkState)")
            }
        }
    }

    /// 稼働中に条件が崩れたら、全状態でリンクを停止し通知を取り下げ、記録中なら停止を要求します。
    ///
    /// 責務: サインアウト・既定削除・Classic・シリアル・監視停止の各条件で、状態ごとの巻き戻しとリンク停止を確認します。
    func testOperatingConditionsLostTearDownEveryStateAndStopLink() {
        let lostConditions: [AdapterLinkSupervisionConditions] = [
            F.conditions(isSignedIn: false),
            F.conditions(defaultAdapterPreference: nil),
            F.conditions(defaultAdapterPreference: F.classicPreference),
            F.conditions(defaultAdapterPreference: F.serialPreference),
            F.conditions(isSupervisionStarted: false),
        ]
        for state in F.allStates {
            let expected = expectedConditionsLostTeardown(from: state)
            for conditions in lostConditions {
                let result = transition.operatingConditionsChanged(from: state, conditions: conditions)
                A.assertResult(result, state: expected.state, effects: expected.effects + [.stopLink], "\(state)")
                XCTAssertFalse(result.effects.contains { if case .startLink = $0 { true } else { false } }, "\(state)")
            }
        }
    }

    /// 別のBLEアダプターへ変わったら、全状態で巻き戻してリンクを止め、新しい設定で開始し直します。
    ///
    /// 責務: 停止が開始より前に出ること、開始の引数が新しい設定であることを確認します。
    func testOperatingConditionsSwitchToOtherBLERestartsLinkInEveryState() {
        let conditions = F.conditions(defaultAdapterPreference: F.otherBLEPreference, linkPreference: F.blePreference)
        for state in F.allStates {
            let expected = expectedConditionsLostTeardown(from: state)
            let result = transition.operatingConditionsChanged(from: state, conditions: conditions)
            A.assertResult(
                result, state: expected.state, effects: expected.effects + [.stopLink, .prepareNotifications, .startLink(F.otherBLEPreference)], "\(state)"
            )
            let stopIndex = result.effects.firstIndex(of: .stopLink)
            let startIndex = result.effects.firstIndex(of: .startLink(F.otherBLEPreference))
            XCTAssertNotNil(stopIndex, "\(state)")
            XCTAssertNotNil(startIndex, "\(state)")
            if let stopIndex, let startIndex { XCTAssertLessThan(stopIndex, startIndex, "\(state)") }
        }
    }

    /// 進行中の初期化・確認・VIN読取がある状態で条件が崩れたら、その処理を取り消します。
    ///
    /// 責務: 後から届く古い結果を無効にする取り消しが巻き戻しに含まれることを確認します。
    func testOperatingConditionsLostCancelInFlightOperations() {
        let inFlight: [AdapterLinkSupervisionState] = [
            .initializing(linkReadyAt: F.referenceDate),
            .confirmingVehicle(F.confirmation(phase: .probing)),
            .vehicleDetected(AdapterLinkDetectedVehicle(adapterProbeEvidence: F.evidence, vin: nil), phase: .readingVIN),
        ]
        for state in inFlight {
            let result = transition.operatingConditionsChanged(from: state, conditions: F.conditions(isSignedIn: false))
            XCTAssertTrue(result.effects.contains(.cancelOperations), "\(state)")
        }
    }

    /// 開始していないリンクの状態変化は、全状態・全リンク状態で無視します。
    ///
    /// 責務: 接続対象のないリンクの `ready` で初期化しないこと、切断で巻き戻さないことを確認します。
    func testLinkStateChangeWithoutStartedLinkIsIgnored() {
        for state in F.allStates {
            for linkState in nonReadyLinkStates + [.ready] {
                let conditions = F.conditions(linkPreference: nil, linkState: .connecting)
                let result = transition.linkStateChanged(to: linkState, from: state, conditions: conditions)
                A.assertIgnored(result, from: state, "\(state) \(linkState)")
            }
        }
    }

    /// 待機中にリンクが `ready` になったら、その時刻を起点に初期化を始めます。
    ///
    /// 責務: 直前の全ての非 `ready` 状態から、`initializing(linkReadyAt: now)` と初期化の作用になることを確認します。
    func testLinkReadyFromStandbyStartsInitialization() {
        let now = F.date(42)
        for previous in nonReadyLinkStates {
            let result = transition.linkStateChanged(to: .ready, from: .standby, conditions: F.conditions(linkState: previous, now: now))
            A.assertResult(result, state: .initializing(linkReadyAt: now), effects: [.initializeAdapter], "\(previous)")
        }
    }

    /// 同じ `ready` の再通知では初期化を二重に始めません。
    ///
    /// 責務: 直前も `ready` の待機で `ready` が届いても無視することを確認します。
    func testRepeatedLinkReadyInStandbyIsIgnored() {
        let result = transition.linkStateChanged(to: .ready, from: .standby, conditions: F.conditions(linkState: .ready))
        A.assertIgnored(result, from: .standby)
    }

    /// 待機以外の状態で届いた `ready` は無視します。
    ///
    /// 責務: 初期化・確認・検知済み・記録中・終了中では、直前のリンク状態にかかわらず状態も作用も変えないことを確認します。
    func testLinkReadyOutsideStandbyIsIgnored() {
        for state in F.allStates where state != .standby {
            for previous in [AdapterLinkState.ready, .discovering] {
                let result = transition.linkStateChanged(to: .ready, from: state, conditions: F.conditions(linkState: previous))
                A.assertIgnored(result, from: state, "\(state) \(previous)")
            }
        }
    }

    /// `ready` からのリンク断では、記録中は停止を要求せず記録中のまま、それ以外は通知を取り下げて巻き戻し、リンクは止めません。
    ///
    /// 責務: 記録中は記録中のまま(取得ループの猶予に任せる)、終了中は終了のまま、その他は待機へ戻ることを全ての非 `ready` 状態で確認します(U2 受け入れ条件 1)。
    func testLinkLostFromReadyTearsDownEveryStateWithoutStoppingLink() {
        for state in F.allStates {
            for linkState in nonReadyLinkStates {
                let result = transition.linkStateChanged(to: linkState, from: state, conditions: F.conditions(linkState: .ready))
                assertLinkLossResult(result, from: state, "\(state) \(linkState)")
            }
        }
    }

    /// 記録中にリンクが切れた後、非 `ready` どうしの変化が続いても記録中のままです。
    ///
    /// 責務: 再接続の手順(接続中→探索中など)の通知で停止要求が出ないことを確認します(U2 受け入れ条件 1)。
    func testNonReadyChangesAfterLinkLossWhileRecordingKeepRecording() {
        let recording = AdapterLinkSupervisionState.recording(F.detectedVehicle)
        for previous in nonReadyLinkStates {
            for linkState in nonReadyLinkStates where linkState != previous {
                let result = transition.linkStateChanged(to: linkState, from: recording, conditions: F.conditions(linkState: previous))
                A.assertRecordingContinuesAfterLinkLoss(result, from: recording, "\(previous) → \(linkState)")
            }
        }
    }

    /// 進行中の処理がある状態でリンクが切れたら、その処理を取り消します。
    ///
    /// 責務: 初期化中・確認中・VIN読取中のリンク断で取り消しが含まれることを確認します。
    func testLinkLostCancelsInFlightOperations() {
        let inFlight: [AdapterLinkSupervisionState] = [
            .initializing(linkReadyAt: F.referenceDate),
            .confirmingVehicle(F.confirmation(phase: .probing)),
            .vehicleDetected(AdapterLinkDetectedVehicle(adapterProbeEvidence: F.evidence, vin: nil), phase: .readingVIN),
        ]
        for state in inFlight {
            let result = transition.linkStateChanged(to: .connecting, from: state, conditions: F.conditions(linkState: .ready))
            XCTAssertTrue(result.effects.contains(.cancelOperations), "\(state)")
        }
    }

    /// 待機中に非 `ready` の状態どうしで変化しても何もしません。
    ///
    /// 責務: `ready` を経ていない接続手順の進行(接続中→探索中など)を「リンク断」として扱わないことを確認します。
    func testNonReadyToNonReadyInStandbyIsIgnored() {
        let result = transition.linkStateChanged(
            to: .discovering, from: .standby, conditions: F.conditions(linkState: .connecting)
        )
        A.assertIgnored(result, from: .standby)
    }

    /// `tornDown(from:)`(リンクを失ったときの巻き戻し)は全状態で、仕様どおりの巻き戻し先へ移します。
    ///
    /// 責務: 巻き戻しの公開メソッド単体で、記録中は停止を要求せず記録中のまま、それ以外は状態ごとの次の状態と作用(リンク停止なし)を確認します(U2 受け入れ条件 1)。
    func testTornDownForEveryState() {
        for state in F.allStates {
            assertLinkLossResult(transition.tornDown(from: state), from: state, "\(state)")
        }
    }
}
