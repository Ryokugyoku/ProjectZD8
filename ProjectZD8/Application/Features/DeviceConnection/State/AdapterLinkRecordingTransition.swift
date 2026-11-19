import Foundation

/// 車両検知後の通知・記録開始と、記録終了から待機へ戻るまでを決める純粋な遷移です。
nonisolated struct AdapterLinkRecordingTransition: Sendable {
    /// 記録開始が辞退・失敗で終わった後、再初期化までに挟む待ちの秒数です(窓後の再確認間隔と同じ)。
    private let declinedRecordingRetryInterval: TimeInterval

    /// 辞退・失敗後の待ちの秒数を時間定数から固定して生成します。
    ///
    /// 責務: 記録終了後の再確認の待ちを、窓後の再確認間隔(`extendedConfirmationInterval`)へ結び付けます。
    /// - Parameter timing: 監視の時間定数。既定は本番用の定数。
    init(timing: AdapterLinkSupervisionTiming = .standard) {
        declinedRecordingRetryInterval = timing.extendedConfirmationInterval
    }

    /// VIN読取の結果に対する遷移を返します。
    ///
    /// 責務: VIN読取中であれば、自動記録オン(または有効期限内の記録開始の意思あり)なら記録開始を要求して記録中へ、
    /// それ以外は検知通知を1回提示して操作待ちへ移します。「記録を開始しました」通知は開始の確定(`recordingStartConfirmed`)の後に出します。
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
        guard isAutomaticRecordingEnabled || conditions.hasValidRecordingIntent else {
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
            effects: [.requestRecordingStart(AdapterLinkRecordingStartRequest(preference: linkPreference, vehicle: vehicle))]
        )
    }

    /// 記録開始の確定に対する遷移を返します。
    ///
    /// 責務: 記録中で、自動記録で始めた記録なら「記録を開始しました」通知を出します。状態は変えません。
    /// 記録中以外(既に終わった・別の段階)に届いた確定は、古い結果として無視します。
    /// - Parameters:
    ///   - announcesStart: 「記録を開始しました」を出すべき記録か。
    ///   - state: 現在の監視状態。
    /// - Returns: 記録中かつ通知すべきなら `[.presentRecordingStarted(vin:)]`、それ以外は何もしない遷移。
    func recordingStartConfirmed(
        announcesStart: Bool,
        from state: AdapterLinkSupervisionState
    ) -> AdapterLinkSupervisionTransitionResult {
        guard case let .recording(vehicle) = state, announcesStart else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        return AdapterLinkSupervisionTransitionResult(state: state, effects: [.presentRecordingStarted(vin: vehicle.vin)])
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
    /// 責務: 記録中なら記録中からの終了として扱い(`finishedWhileRecording`)、終了中なら待機へ戻します。
    /// - Parameters:
    ///   - endReason: テレメトリの終了理由。記録が始まらなかった・辞退した・手動記録に置き換えた場合は `nil`。
    ///   - state: 現在の監視状態。
    ///   - conditions: 直前のリンク状態を含む条件。
    /// - Returns: 次の状態と作用。それ以外の状態では何もしません。
    func recordingDidFinish(
        endReason: ConnectionSessionEndReason?,
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        switch state {
        case .recording:
            finishedWhileRecording(endReason: endReason, conditions: conditions)
        case .finishing:
            AdapterLinkSupervisionTransitionResult(state: .standby)
        case .standby, .initializing, .confirmingVehicle, .vehicleDetected, .heldAfterUserStop:
            AdapterLinkSupervisionTransitionResult(state: state)
        }
    }

    /// 記録中に届いた記録終了通知に対する遷移を返します。
    ///
    /// 責務: ユーザー切断なら抑止へ移し(`heldAfterUserStop(conditions:)`)、それ以外は通知を取り下げて終了へ移し終了処理の完了を促します。
    /// 終了理由なし(記録開始の辞退・失敗)でリンクが `ready` なら、窓後の再確認間隔の待ちを予約し、待ち明け
    /// (`adapterInitializationRetryElapsed`)で再初期化させます。待ちを挟まずには再開しません。
    /// 手動接続の使用中かどうかでは結果を変えません(待ち明けの時点の条件で遷移側が判定します)。
    /// - Parameters:
    ///   - endReason: テレメトリの終了理由。
    ///   - conditions: 直前のリンク状態と現在時刻を含む条件。
    /// - Returns: 次の状態と作用。
    private func finishedWhileRecording(
        endReason: ConnectionSessionEndReason?,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        if endReason == .userDisconnected {
            return heldAfterUserStop(conditions: conditions)
        }
        var effects: [AdapterLinkSupervisionEffect] = [.dismissNotification, .completeFinishing]
        if endReason == nil, conditions.isLinkReady {
            effects.append(.scheduleAdapterInitializationRetry(after: .seconds(declinedRecordingRetryInterval)))
        }
        return AdapterLinkSupervisionTransitionResult(state: .finishing, effects: effects)
    }

    /// 記録中のユーザー切断に対する抑止への遷移を返します。
    ///
    /// 責務: リンクが `ready` のままなら、終了中を経ずに抑止状態へ移し、同じリンク接続のあいだ再検知しません。
    /// リンクが `ready` でない(リンク断で一時停止中など)なら、終了中を経ずにリンク待ちの保持へ移します
    /// (切断の時刻から上限以内にリンクが戻れば同じ走行とみなすため。アダプターへは何も送りません)。
    /// - Parameter conditions: 直前のリンク状態と現在時刻を含む条件。
    /// - Returns: 抑止への遷移と通知の取り下げ。
    private func heldAfterUserStop(conditions: AdapterLinkSupervisionConditions) -> AdapterLinkSupervisionTransitionResult {
        let watch: AdapterLinkHeldWatch = conditions.isLinkReady ? .awaitingStart : .awaitingLink(userStoppedAt: conditions.now)
        return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch), effects: [.dismissNotification])
    }

    /// 記録の終了通知を受けて終了処理が落ち着いた後の、待機からの検知のやり直しを返します。
    ///
    /// 責務: 記録がユーザー切断以外の理由で終わって待機へ戻った時に、リンクが `ready` で手動接続が使っていなければ、
    /// その時刻を窓の起点として初期化からやり直します。リンクが `ready` でなければ待機のまま次の再接続を待ちます。
    /// 記録中・終了処理中にはアダプターへ何も送らないため、このイベントは記録の終了通知の後にだけ届きます。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - conditions: リンク状態と現在時刻を含む条件。
    /// - Returns: 次の状態と作用。待機以外(抑止中は見張りの遷移が扱う)と、始められない条件では何もしません。
    func recordingEndSettled(
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard state == .standby, conditions.isLinkReady, !conditions.isExternalAdapterUseActive else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        return AdapterLinkSupervisionTransitionResult(state: .initializing(linkReadyAt: conditions.now), effects: [.initializeAdapter])
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
