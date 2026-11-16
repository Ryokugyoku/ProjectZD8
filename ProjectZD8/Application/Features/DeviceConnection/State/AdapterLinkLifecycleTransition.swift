/// 稼働条件とリンク状態の変化から、リンクの開始・停止と監視の巻き戻しを決める純粋な遷移です。
///
/// 原因ごとに遷移を分けます。リンク断は記録を止めず(`linkLost(from:)`)、稼働条件の喪失・接続対象の変更は
/// 理由を付けて記録の停止を要求します(`AdapterLinkRecordingStopTransition`)。
nonisolated struct AdapterLinkLifecycleTransition: Sendable {
    /// 稼働条件の喪失・接続対象の変更で記録を終わらせる遷移です。
    private let recordingStop = AdapterLinkRecordingStopTransition()

    /// 稼働条件の変化に対する遷移を返します。
    ///
    /// 責務: 稼働条件から決まる接続対象と開始済みリンクの接続対象を比べ、停止・開始し直し・開始を決めます。
    /// 開始済みリンクを止める時は、記録中なら理由(`AdapterLinkRecordingStopReason.forOperatingConditionsChange`)を付けて停止を要求します。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - conditions: 変化後の条件。
    /// - Returns: 次の状態と作用。接続対象が変わらない場合は状態も作用も変えません。
    func operatingConditionsChanged(
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        let targetPreference = conditions.operatingPreference
        guard targetPreference != conditions.linkPreference else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }

        var nextState = state
        var effects: [AdapterLinkSupervisionEffect] = []
        if conditions.linkPreference != nil {
            let teardown = recordingStop.stopped(
                from: state,
                reason: .forOperatingConditionsChange(conditions)
            )
            nextState = teardown.state
            effects += teardown.effects + [.stopLink]
        }
        if let targetPreference {
            effects += [.prepareNotifications, .startLink(targetPreference)]
        }
        return AdapterLinkSupervisionTransitionResult(state: nextState, effects: effects)
    }

    /// リンク状態の変化に対する遷移を返します。
    ///
    /// 責務: `ready` への変化を初期化の開始へ、`ready` 以外への変化をリンク断の巻き戻し(`linkLost(from:)`)へ変換します。
    /// - Parameters:
    ///   - linkState: 変化後のリンク状態。
    ///   - state: 現在の監視状態。
    ///   - conditions: 直前のリンク状態を含む条件。
    /// - Returns: 次の状態と作用。開始していないリンクの変化と、同じ状態の再通知は無視します。
    ///   手動接続がアダプターを使っている最中は `ready` になっても初期化を始めません。
    ///   記録中に `ready` へ戻っても初期化・車両確認をやり直しません(復帰に要る初期化は取得側の回復操作が行います)。
    func linkStateChanged(
        to linkState: AdapterLinkState,
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard conditions.linkPreference != nil else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        if linkState == .ready {
            guard conditions.linkState != .ready, state == .standby, !conditions.isExternalAdapterUseActive else {
                return AdapterLinkSupervisionTransitionResult(state: state)
            }
            return AdapterLinkSupervisionTransitionResult(
                state: .initializing(linkReadyAt: conditions.now),
                effects: [.initializeAdapter]
            )
        }
        guard conditions.linkState == .ready || state != .standby else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        return linkLost(from: state)
    }

    /// リンクを失ったときの巻き戻し先と作用を返します。
    ///
    /// 責務: 進行中の処理の取り消しと通知の取り下げを行います。記録中は停止を要求せず記録中のまま
    /// (取得側の途切れ処理と猶予に任せ、記録の終了通知を受けてから待機へ戻ります)、終了中は終了のまま、それ以外は待機へ戻します。
    /// - Parameter state: 現在の監視状態。
    /// - Returns: 記録中は `recording` のまま、終了中は `finishing`、それ以外(抑止中を含む)は `standby` への遷移。
    func linkLost(from state: AdapterLinkSupervisionState) -> AdapterLinkSupervisionTransitionResult {
        switch state {
        case .recording:
            AdapterLinkSupervisionTransitionResult(state: state, effects: [.cancelOperations, .dismissNotification])
        case .finishing:
            AdapterLinkSupervisionTransitionResult(state: .finishing, effects: [.cancelOperations, .dismissNotification])
        case .standby, .initializing, .confirmingVehicle, .vehicleDetected, .heldAfterUserStop:
            AdapterLinkSupervisionTransitionResult(state: .standby, effects: [.cancelOperations, .dismissNotification])
        }
    }
}
