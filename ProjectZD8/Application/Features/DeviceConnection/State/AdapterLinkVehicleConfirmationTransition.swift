import Foundation

/// アダプター初期化から車両検知までと、前面復帰による再開を決める純粋な遷移です。
///
/// 確認は応答駆動です。確認の結果を受け取ったことを次の確認の起点にし、固定の待機を挟みません。無応答の間の頻度は
/// アダプター側の最大タイムアウト(`ATSTFF`)で決まります。結果が最短間隔より早く返った時だけ残り時間を待ちます
/// (`AdapterLinkVehicleConfirmationPacing`)。窓と回数の上限は結果を受け取るたびに判定し(`AdapterLinkVehicleConfirmationWindowPolicy`)、
/// アプリが前面にいる間は窓切れで窓を取り直します。背面では窓切れ・回数の上限の後も休止せず、
/// 窓後の間隔(`AdapterLinkSupervisionTiming.extendedConfirmationInterval`)でリンクが `ready` の間は無期限に続けます。
nonisolated struct AdapterLinkVehicleConfirmationTransition: Sendable {
    /// 確認窓と最短間隔の定数です。
    let timing: AdapterLinkSupervisionTiming

    /// 窓と回数の上限の判定です。
    private let windowPolicy: AdapterLinkVehicleConfirmationWindowPolicy

    /// 最短間隔の判定です。
    private let pacing: AdapterLinkVehicleConfirmationPacing

    /// 窓後の再確認間隔の判定です。
    private let extendedPacing: AdapterLinkVehicleConfirmationPacing

    /// 確認窓と最短間隔を固定して生成します。
    ///
    /// 責務: 車両確認の時間定数を遷移と判定へ結び付けます。
    /// - Parameter timing: 確認窓と最短間隔。
    init(timing: AdapterLinkSupervisionTiming) {
        self.timing = timing
        windowPolicy = AdapterLinkVehicleConfirmationWindowPolicy(timing: timing)
        pacing = AdapterLinkVehicleConfirmationPacing(minimumInterval: timing.vehicleConfirmationInterval)
        extendedPacing = AdapterLinkVehicleConfirmationPacing(minimumInterval: timing.extendedConfirmationInterval)
    }

    /// アダプター初期化の成功に対する遷移を返します。
    ///
    /// 責務: 初期化中であれば、リンクが `ready` になった時刻を起点に確認窓を開き、通常のタイムアウトで最初の確認を要求します。
    /// - Parameters:
    ///   - evidence: 初期化で得たアダプター判定結果。
    ///   - state: 現在の監視状態。
    /// - Returns: 次の状態と作用。初期化中以外では何もしません。
    func adapterInitializationSucceeded(
        _ evidence: AcquisitionAdapterProbeEvidence,
        from state: AdapterLinkSupervisionState
    ) -> AdapterLinkSupervisionTransitionResult {
        guard case let .initializing(linkReadyAt) = state else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        let confirmation = AdapterLinkVehicleConfirmation(
            adapterProbeEvidence: evidence,
            windowEndsAt: linkReadyAt.addingTimeInterval(timing.vehicleConfirmationWindow),
            attemptCount: 1,
            phase: .probing
        )
        return AdapterLinkSupervisionTransitionResult(
            state: .confirmingVehicle(confirmation),
            effects: [.confirmVehicle(.standard)]
        )
    }

    /// アダプター初期化の失敗に対する遷移を返します。
    ///
    /// 責務: 初期化中であれば待機へ戻します。リンクが `ready` で手動接続がアダプターを使っていなければ、
    /// 設定した間隔(既定60秒)後の再初期化を予約します(`.scheduleAdapterInitializationRetry`)。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - conditions: リンク状態と手動接続の使用状況を含む条件。
    /// - Returns: 初期化中なら `standby`(と条件を満たす場合の再試行の予約)、それ以外では何もしない遷移。
    func adapterInitializationFailed(
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard case .initializing = state else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        guard conditions.canStartAdapterWork else {
            return AdapterLinkSupervisionTransitionResult(state: .standby)
        }
        return AdapterLinkSupervisionTransitionResult(
            state: .standby,
            effects: [.scheduleAdapterInitializationRetry(after: .seconds(timing.initializationRetryInterval))]
        )
    }

    /// 初期化の再試行の待機が終わったときの遷移を返します。
    ///
    /// 責務: 待機でリンクが `ready` かつ手動接続がアダプターを使っていなければ、初期化からやり直します。
    /// 予約の発火時点で条件を満たさなければ何もしません。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - conditions: リンク状態・手動接続の使用状況・現在時刻を含む条件。
    /// - Returns: 条件を満たす待機なら `initializing(linkReadyAt: now)` と初期化の作用。それ以外は何もしません。
    func adapterInitializationRetryElapsed(
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        reinitializedFromStandby(from: state, conditions: conditions)
    }

    /// 待機でリンクが `ready` なら、すぐ初期化からやり直す遷移を返します。
    ///
    /// 責務: 待機・リンク `ready`・手動接続なしの3条件を満たすときだけ、現在時刻を起点に初期化を始めます。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - conditions: リンク状態・手動接続の使用状況・現在時刻を含む条件。
    /// - Returns: 条件を満たす待機なら `initializing(linkReadyAt: now)` と初期化の作用。それ以外は何もしません。
    func reinitializedFromStandby(
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard state == .standby, conditions.canStartAdapterWork else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        return AdapterLinkSupervisionTransitionResult(
            state: .initializing(linkReadyAt: conditions.now),
            effects: [.initializeAdapter]
        )
    }

    /// 車両確認の完了に対する遷移を返します。
    ///
    /// 責務: 低頻度確認中であれば、応答ありを検知へ、無応答を次の確認(応答駆動。最短間隔より早ければ残り時間の待機)か
    /// 窓の取り直しか窓後の間隔での確認へ変換します。休止はしません。
    /// - Parameters:
    ///   - outcome: ECU応答の有無。
    ///   - state: 現在の監視状態。
    ///   - conditions: 結果を受け取った時刻・前面かどうか・最後に確認を送った時刻を含む条件。
    /// - Returns: 次の状態と作用。低頻度確認中以外では何もしません。
    ///   無応答は、リンクが `ready` でない・手動接続が使用中なら確認も予約もしません。
    func vehicleConfirmationCompleted(
        _ outcome: VehicleResponseOutcome,
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard case let .confirmingVehicle(confirmation) = state, confirmation.phase == .probing else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        switch outcome {
        case .responding:
            let vehicle = AdapterLinkDetectedVehicle(adapterProbeEvidence: confirmation.adapterProbeEvidence, vin: nil)
            return AdapterLinkSupervisionTransitionResult(
                state: .vehicleDetected(vehicle, phase: .readingVIN),
                effects: [.readVIN]
            )
        case .noResponse:
            return noResponseResult(confirmation, state: state, conditions: conditions)
        }
    }

    /// 無応答を受けたときの次の確認を決める遷移を返します。
    ///
    /// 責務: 窓の判定と最短間隔(窓後は窓後の間隔)から、確認を送る・残り時間だけ待つ・窓を取り直す・何もしないを選びます。
    /// - Parameters:
    ///   - confirmation: 現在の確認進行状況。
    ///   - state: 現在の監視状態(確認中)。
    ///   - conditions: 結果を受け取った時刻・前面かどうか・最後に確認を送った時刻を含む条件。
    /// - Returns: 次の状態と作用。確認を始められない条件では何もしません。
    private func noResponseResult(
        _ confirmation: AdapterLinkVehicleConfirmation,
        state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard conditions.canStartAdapterWork else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        let decision = windowPolicy.decision(for: confirmation, now: conditions.now, isForeground: conditions.isForeground)
        let activePacing = decision == .extendedConfirmation ? extendedPacing : pacing
        guard let wait = activePacing.remainingWait(sentAt: conditions.lastVehicleConfirmationSentAt, now: conditions.now) else {
            return confirmAgain(confirmation, decision: decision, now: conditions.now)
        }
        return AdapterLinkSupervisionTransitionResult(state: state, effects: [.scheduleVehicleConfirmation(after: wait)])
    }

    /// 最短間隔の残り時間の待機が終わったときの遷移を返します。
    ///
    /// 責務: 低頻度確認中であれば、窓と回数の上限を判定し直して、最大タイムアウトで次の確認を送るか、窓を取り直します。
    /// 窓後は休止せず確認を続けます。待ち明けの後に最短間隔を測り直して待ち直すことはしません。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - conditions: 待ち明けの時刻と前面かどうかを含む条件。
    /// - Returns: 次の状態と作用。低頻度確認中以外では何もしません。
    ///   リンクが `ready` でない・手動接続が使用中なら確認しません。
    func vehicleConfirmationIntervalElapsed(
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard case let .confirmingVehicle(confirmation) = state, confirmation.phase == .probing,
              conditions.canStartAdapterWork else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        let decision = windowPolicy.decision(for: confirmation, now: conditions.now, isForeground: conditions.isForeground)
        return confirmAgain(confirmation, decision: decision, now: conditions.now)
    }

    /// アプリの前面復帰に対する遷移を返します。
    ///
    /// 責務: リンクが `ready` の待機からは初期化をやり直し、休止中の車両確認は確認窓を取り直して再開し、
    /// 確認中で窓が既に切れていれば確認を重複させずに窓だけ取り直します。窓の内の確認中は何もしません。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - conditions: リンク状態と現在時刻を含む条件。
    /// - Returns: 次の状態と作用。それ以外の状態と、手動接続がアダプターを使っている最中は何もしません。
    func appDidBecomeActive(
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard !conditions.isExternalAdapterUseActive else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        switch state {
        case .standby where conditions.isLinkReady:
            return reinitializedFromStandby(from: state, conditions: conditions)
        case let .confirmingVehicle(confirmation) where confirmation.phase == .paused:
            return AdapterLinkSupervisionTransitionResult(
                state: .confirmingVehicle(windowPolicy.renewed(confirmation, at: conditions.now)),
                effects: [.confirmVehicle(.adapterMaximum)]
            )
        case let .confirmingVehicle(confirmation) where !windowPolicy.isInsideWindow(confirmation, now: conditions.now):
            // 確認中に窓が切れていた(サスペンド中など)。確認の結果か待ち明けが届くので、確認は重複させず窓だけ取り直します。
            return AdapterLinkSupervisionTransitionResult(
                state: .confirmingVehicle(windowPolicy.renewed(confirmation, at: conditions.now))
            )
        default:
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
    }

    /// 同じ窓で(または取り直した窓で)最大タイムアウトの確認を1回送る遷移を返します。
    ///
    /// 責務: 窓の判定が続行なら回数を1増やし、取り直し(前面での窓切れ・回数の上限)なら窓と回数を取り直し、
    /// 窓後の確認(背面での窓切れ・回数の上限)なら進行状況を変えずに、`.adapterMaximum` の確認を要求します。
    /// - Parameters:
    ///   - confirmation: 現在の確認進行状況。
    ///   - decision: 窓と回数の判定結果。
    ///   - now: 現在時刻。取り直す窓の起点です。
    /// - Returns: 確認中への遷移と確認の作用。
    private func confirmAgain(
        _ confirmation: AdapterLinkVehicleConfirmation,
        decision: AdapterLinkVehicleConfirmationWindowDecision,
        now: Date
    ) -> AdapterLinkSupervisionTransitionResult {
        let next: AdapterLinkVehicleConfirmation
        switch decision {
        case .continueInWindow:
            next = AdapterLinkVehicleConfirmation(
                adapterProbeEvidence: confirmation.adapterProbeEvidence,
                windowEndsAt: confirmation.windowEndsAt,
                attemptCount: confirmation.attemptCount + 1,
                phase: .probing
            )
        case .renewWindow:
            next = windowPolicy.renewed(confirmation, at: now)
        case .extendedConfirmation:
            next = confirmation
        }
        return AdapterLinkSupervisionTransitionResult(state: .confirmingVehicle(next), effects: [.confirmVehicle(.adapterMaximum)])
    }
}
