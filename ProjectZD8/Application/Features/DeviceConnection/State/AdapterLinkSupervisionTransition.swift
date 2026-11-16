/// 常駐リンク監視の `(現在の状態, イベント, 条件) → (次の状態, 作用の列)` を返す純粋な遷移です。
///
/// 分岐はイベントの種類ごとに `AdapterLinkLifecycleTransition`・`AdapterLinkVehicleConfirmationTransition`・
/// `AdapterLinkRecordingTransition` へ委ね、ユーザー切断後の抑止中の確認・前面復帰・記録終了後の再開は
/// `AdapterLinkHeldWatchTransition` へ委ねます。
nonisolated struct AdapterLinkSupervisionTransition: Sendable {
    /// 稼働条件とリンク状態の変化を扱う遷移です。
    private let lifecycle = AdapterLinkLifecycleTransition()

    /// 初期化から車両検知までと前面復帰を扱う遷移です。
    private let confirmation: AdapterLinkVehicleConfirmationTransition

    /// 検知後の通知・記録開始・記録終了を扱う遷移です。
    private let recording = AdapterLinkRecordingTransition()

    /// 手動接続によるアダプター使用の開始・終了の遷移です。
    private let externalAdapterUse = AdapterLinkExternalAdapterUseTransition()

    /// ユーザー切断後の抑止中の見張りの遷移です。
    private let heldWatch: AdapterLinkHeldWatchTransition

    /// 確認窓と再確認間隔を固定して生成します。
    ///
    /// 責務: 車両確認の時間定数を遷移全体へ結び付けます。
    /// - Parameter timing: 確認窓と再確認間隔。既定は本番用の定数。
    init(timing: AdapterLinkSupervisionTiming = .standard) {
        confirmation = AdapterLinkVehicleConfirmationTransition(timing: timing)
        heldWatch = AdapterLinkHeldWatchTransition(timing: timing)
    }

    /// 1件のイベントに対する次の状態と作用の列を返します。
    ///
    /// 責務: イベントの種類に応じて担当の遷移へ振り分けます。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - event: 入力されたイベント。
    ///   - conditions: 状態以外の現在の条件。
    /// - Returns: 次の状態と順に実行する作用。
    func result(
        from state: AdapterLinkSupervisionState,
        on event: AdapterLinkSupervisionEvent,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        switch event {
        case .operatingConditionsChanged:
            lifecycle.operatingConditionsChanged(from: state, conditions: conditions)
        case let .linkStateChanged(linkState):
            lifecycle.linkStateChanged(to: linkState, from: state, conditions: conditions)
        case .vehicleConfirmationCompleted, .vehicleConfirmationFailed, .vehicleConfirmationIntervalElapsed,
             .appDidBecomeActive, .recordingEndSettled:
            if case let .heldAfterUserStop(watch) = state {
                heldWatchResult(watch, on: event, conditions: conditions)
            } else {
                confirmationResult(from: state, on: event, conditions: conditions)
            }
        case .adapterInitializationSucceeded, .adapterInitializationFailed:
            confirmationResult(from: state, on: event, conditions: conditions)
        case .vinReadCompleted, .vinReadFailed, .recordingStartSelected, .recordingDidFinish, .finishingDidComplete,
             .recordingStartConfirmed:
            recordingResult(from: state, on: event, conditions: conditions)
        case .externalAdapterUseBegan:
            if case let .heldAfterUserStop(watch) = state {
                heldWatch.externalAdapterUseBegan(watch)
            } else {
                externalAdapterUse.began(from: state)
            }
        case .externalAdapterUseEnded:
            if case let .heldAfterUserStop(watch) = state {
                heldWatch.externalAdapterUseEnded(watch, conditions: conditions)
            } else {
                externalAdapterUse.ended(from: state)
            }
        }
    }

    /// 初期化・車両確認・前面復帰のイベントを担当の遷移へ渡します。
    ///
    /// 責務: 車両確認系イベントの引数を取り出し、確認失敗を無応答と同じ扱いへ揃えて委ねます。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - event: 車両確認系のイベント。
    ///   - conditions: 状態以外の現在の条件。
    /// - Returns: 次の状態と作用。
    private func confirmationResult(
        from state: AdapterLinkSupervisionState,
        on event: AdapterLinkSupervisionEvent,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        switch event {
        case let .adapterInitializationSucceeded(evidence):
            confirmation.adapterInitializationSucceeded(evidence, from: state)
        case .adapterInitializationFailed:
            confirmation.adapterInitializationFailed(from: state)
        case let .vehicleConfirmationCompleted(outcome):
            confirmation.vehicleConfirmationCompleted(outcome, from: state, conditions: conditions)
        case .vehicleConfirmationFailed:
            confirmation.vehicleConfirmationCompleted(.noResponse, from: state, conditions: conditions)
        case .vehicleConfirmationIntervalElapsed:
            confirmation.vehicleConfirmationIntervalElapsed(from: state, conditions: conditions)
        case .appDidBecomeActive:
            confirmation.appDidBecomeActive(from: state, conditions: conditions)
        case .recordingEndSettled:
            recording.recordingEndSettled(from: state, conditions: conditions)
        default:
            AdapterLinkSupervisionTransitionResult(state: state)
        }
    }

    /// 抑止中の確認・前面復帰・記録終了後の再開のイベントを見張りの遷移へ渡します。
    ///
    /// 責務: イベントの引数を取り出して委ねます。抑止中の確認失敗は無応答と数えません。
    /// - Parameters:
    ///   - watch: 現在の見張りの進行状況。
    ///   - event: 確認系・前面復帰・記録終了後の再開のイベント。
    ///   - conditions: 状態以外の現在の条件。
    /// - Returns: 次の状態と作用。
    private func heldWatchResult(
        _ watch: AdapterLinkHeldWatch,
        on event: AdapterLinkSupervisionEvent,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        switch event {
        case let .vehicleConfirmationCompleted(outcome):
            heldWatch.confirmationCompleted(outcome, watch: watch, conditions: conditions)
        case .vehicleConfirmationFailed:
            heldWatch.confirmationFailed(watch, conditions: conditions)
        case .vehicleConfirmationIntervalElapsed:
            heldWatch.intervalElapsed(watch, conditions: conditions)
        case .appDidBecomeActive:
            heldWatch.appDidBecomeActive(watch, conditions: conditions)
        case .recordingEndSettled:
            heldWatch.recordingEndSettled(watch, conditions: conditions)
        default:
            AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch))
        }
    }

    /// 検知後・記録系のイベントを担当の遷移へ渡します。
    ///
    /// 責務: 記録系イベントの引数を取り出し、VIN読取失敗をVINなしの読取完了と同じ扱いへ揃えて委ねます。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - event: 記録系のイベント。
    ///   - conditions: 状態以外の現在の条件。
    /// - Returns: 次の状態と作用。
    private func recordingResult(
        from state: AdapterLinkSupervisionState,
        on event: AdapterLinkSupervisionEvent,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        switch event {
        case let .vinReadCompleted(vin, isAutomaticRecordingEnabled):
            recording.vinReadFinished(
                vin: vin, isAutomaticRecordingEnabled: isAutomaticRecordingEnabled, from: state, conditions: conditions
            )
        case let .vinReadFailed(isAutomaticRecordingEnabled):
            recording.vinReadFinished(
                vin: nil, isAutomaticRecordingEnabled: isAutomaticRecordingEnabled, from: state, conditions: conditions
            )
        case .recordingStartSelected:
            recording.recordingStartSelected(from: state, conditions: conditions)
        case let .recordingDidFinish(endReason):
            recording.recordingDidFinish(endReason: endReason, from: state, conditions: conditions)
        case .finishingDidComplete:
            recording.finishingDidComplete(from: state)
        case let .recordingStartConfirmed(announcesStart):
            recording.recordingStartConfirmed(announcesStart: announcesStart, from: state)
        default:
            AdapterLinkSupervisionTransitionResult(state: state)
        }
    }
}
