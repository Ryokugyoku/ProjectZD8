/// 車両検知後の通知・記録開始と、記録終了から待機へ戻るまでを決める純粋な遷移です。
nonisolated struct AdapterLinkRecordingTransition: Sendable {
    /// VIN読取の結果に対する遷移を返します。
    ///
    /// 責務: VIN読取中であれば、自動記録オンなら記録開始を要求して記録中へ、オフなら検知通知を1回提示して操作待ちへ移します。
    /// - Parameters:
    ///   - vin: 読み取ったVIN。読めなかった・失敗した場合は `nil`。
    ///   - isAutomaticRecordingEnabled: 検知時点の自動記録設定。
    ///   - state: 現在の監視状態。
    ///   - conditions: リンクの接続対象を含む条件。
    /// - Returns: 次の状態と作用。VIN読取中以外では何もしません。
    func vinReadFinished(
        vin: String?,
        isAutomaticRecordingEnabled: Bool,
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard case let .vehicleDetected(detected, .readingVIN) = state else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        let vehicle = AdapterLinkDetectedVehicle(adapterProbeEvidence: detected.adapterProbeEvidence, vin: vin)
        guard isAutomaticRecordingEnabled else {
            return AdapterLinkSupervisionTransitionResult(
                state: .vehicleDetected(vehicle, phase: .awaitingRecordingStart),
                effects: [.presentVehicleDetected(vin: vin)]
            )
        }
        guard let linkPreference = conditions.linkPreference else {
            return AdapterLinkSupervisionTransitionResult(state: .standby, effects: [.cancelOperations])
        }
        return AdapterLinkSupervisionTransitionResult(
            state: .recording(vehicle),
            effects: [
                .requestRecordingStart(AdapterLinkRecordingStartRequest(preference: linkPreference, vehicle: vehicle)),
                .presentRecordingStarted(vin: vin),
            ]
        )
    }

    /// 通知の[記録開始]選択に対する遷移を返します。
    ///
    /// 責務: 記録開始操作待ちの検知済みであれば、検知通知を取り下げて記録開始を要求し記録中へ移します。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - conditions: リンクの接続対象を含む条件。
    /// - Returns: 次の状態と作用。それ以外の状態では記録を始めません。
    func recordingStartSelected(
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard case let .vehicleDetected(vehicle, .awaitingRecordingStart) = state,
              let linkPreference = conditions.linkPreference else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        return AdapterLinkSupervisionTransitionResult(
            state: .recording(vehicle),
            effects: [
                .dismissNotification,
                .requestRecordingStart(AdapterLinkRecordingStartRequest(preference: linkPreference, vehicle: vehicle)),
            ]
        )
    }

    /// 記録側からの記録終了通知に対する遷移を返します。
    ///
    /// 責務: 記録中なら通知を取り下げて終了へ移し終了処理の完了を促し、終了中なら待機へ戻します。
    /// - Parameter state: 現在の監視状態。
    /// - Returns: 次の状態と作用。それ以外の状態では何もしません。
    func recordingDidFinish(from state: AdapterLinkSupervisionState) -> AdapterLinkSupervisionTransitionResult {
        switch state {
        case .recording:
            AdapterLinkSupervisionTransitionResult(state: .finishing, effects: [.dismissNotification, .completeFinishing])
        case .finishing:
            AdapterLinkSupervisionTransitionResult(state: .standby)
        case .standby, .initializing, .confirmingVehicle, .vehicleDetected:
            AdapterLinkSupervisionTransitionResult(state: state)
        }
    }

    /// 終了処理の完了に対する遷移を返します。
    ///
    /// 責務: 終了中であれば待機へ戻します。
    /// - Parameter state: 現在の監視状態。
    /// - Returns: 終了中なら `standby`、それ以外では何もしない遷移。
    func finishingDidComplete(from state: AdapterLinkSupervisionState) -> AdapterLinkSupervisionTransitionResult {
        guard case .finishing = state else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        return AdapterLinkSupervisionTransitionResult(state: .standby)
    }
}
