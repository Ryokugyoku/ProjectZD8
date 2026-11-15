import Foundation

/// アダプター初期化から車両検知までと、前面復帰による再開を決める純粋な遷移です。
nonisolated struct AdapterLinkVehicleConfirmationTransition: Sendable {
    /// 確認窓と再確認間隔の定数です。
    let timing: AdapterLinkSupervisionTiming

    /// 確認窓と再確認間隔を固定して生成します。
    ///
    /// 責務: 車両確認の時間定数を遷移へ結び付けます。
    /// - Parameter timing: 確認窓と再確認間隔。
    init(timing: AdapterLinkSupervisionTiming) {
        self.timing = timing
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
    /// 責務: 初期化中であれば待機へ戻し、次の再接続か前面復帰での再試行に委ねます。
    /// - Parameter state: 現在の監視状態。
    /// - Returns: 初期化中なら `standby`、それ以外では何もしない遷移。
    func adapterInitializationFailed(from state: AdapterLinkSupervisionState) -> AdapterLinkSupervisionTransitionResult {
        guard case .initializing = state else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        return AdapterLinkSupervisionTransitionResult(state: .standby)
    }

    /// 車両確認の完了に対する遷移を返します。
    ///
    /// 責務: 低頻度確認中であれば、応答ありを検知へ、無応答を再確認の予約か休止へ変換します。
    /// - Parameters:
    ///   - outcome: ECU応答の有無。
    ///   - state: 現在の監視状態。
    ///   - now: 現在時刻。
    /// - Returns: 次の状態と作用。低頻度確認中以外では何もしません。
    func vehicleConfirmationCompleted(
        _ outcome: VehicleResponseOutcome,
        from state: AdapterLinkSupervisionState,
        now: Date
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
            return afterNoResponse(confirmation, now: now)
        }
    }

    /// 再確認までの待機が終わったときの遷移を返します。
    ///
    /// 責務: 確認窓と回数の上限内であれば最大タイムアウトで再確認し、上限に達していれば休止します。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - now: 現在時刻。
    /// - Returns: 次の状態と作用。低頻度確認中以外では何もしません。
    func vehicleConfirmationIntervalElapsed(
        from state: AdapterLinkSupervisionState,
        now: Date
    ) -> AdapterLinkSupervisionTransitionResult {
        guard case let .confirmingVehicle(confirmation) = state, confirmation.phase == .probing else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        guard canConfirmAgain(confirmation, now: now) else {
            return AdapterLinkSupervisionTransitionResult(state: .confirmingVehicle(paused(confirmation)))
        }
        let next = AdapterLinkVehicleConfirmation(
            adapterProbeEvidence: confirmation.adapterProbeEvidence,
            windowEndsAt: confirmation.windowEndsAt,
            attemptCount: confirmation.attemptCount + 1,
            phase: .probing
        )
        return AdapterLinkSupervisionTransitionResult(
            state: .confirmingVehicle(next),
            effects: [.confirmVehicle(.adapterMaximum)]
        )
    }

    /// アプリの前面復帰に対する遷移を返します。
    ///
    /// 責務: リンクが `ready` の待機からは初期化をやり直し、休止中の車両確認は確認窓を取り直して再開します。
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
            return AdapterLinkSupervisionTransitionResult(
                state: .initializing(linkReadyAt: conditions.now),
                effects: [.initializeAdapter]
            )
        case let .confirmingVehicle(confirmation) where confirmation.phase == .paused:
            let resumed = AdapterLinkVehicleConfirmation(
                adapterProbeEvidence: confirmation.adapterProbeEvidence,
                windowEndsAt: conditions.now.addingTimeInterval(timing.vehicleConfirmationWindow),
                attemptCount: 1,
                phase: .probing
            )
            return AdapterLinkSupervisionTransitionResult(
                state: .confirmingVehicle(resumed),
                effects: [.confirmVehicle(.adapterMaximum)]
            )
        default:
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
    }

    /// 無応答の後に再確認を予約するか休止するかを返します。
    ///
    /// 責務: 確認窓と回数の上限内なら再確認間隔の待機を予約し、超えていれば休止へ移します。
    /// - Parameters:
    ///   - confirmation: 現在の確認進行状況。
    ///   - now: 現在時刻。
    /// - Returns: 再確認の予約か休止への遷移。
    private func afterNoResponse(
        _ confirmation: AdapterLinkVehicleConfirmation,
        now: Date
    ) -> AdapterLinkSupervisionTransitionResult {
        guard canConfirmAgain(confirmation, now: now) else {
            return AdapterLinkSupervisionTransitionResult(state: .confirmingVehicle(paused(confirmation)))
        }
        return AdapterLinkSupervisionTransitionResult(
            state: .confirmingVehicle(confirmation),
            effects: [.scheduleVehicleConfirmation(after: timing.vehicleConfirmationIntervalDuration)]
        )
    }

    /// 確認窓と回数の上限内で次の確認を要求できるかどうかを返します。
    ///
    /// 責務: 確認窓の終了時刻より前で、かつ確認回数が上限未満であることを判定します。
    /// - Parameters:
    ///   - confirmation: 現在の確認進行状況。
    ///   - now: 現在時刻。
    /// - Returns: 次の確認を要求できる場合は `true`。
    private func canConfirmAgain(_ confirmation: AdapterLinkVehicleConfirmation, now: Date) -> Bool {
        now < confirmation.windowEndsAt && confirmation.attemptCount < timing.maximumVehicleConfirmationAttempts
    }

    /// 確認進行状況を休止へ移した値を返します。
    ///
    /// 責務: アダプター判定結果と確認窓を保ったまま段階だけを休止へ変えます。
    /// - Parameter confirmation: 現在の確認進行状況。
    /// - Returns: 休止中の確認進行状況。
    private func paused(_ confirmation: AdapterLinkVehicleConfirmation) -> AdapterLinkVehicleConfirmation {
        AdapterLinkVehicleConfirmation(
            adapterProbeEvidence: confirmation.adapterProbeEvidence,
            windowEndsAt: confirmation.windowEndsAt,
            attemptCount: confirmation.attemptCount,
            phase: .paused
        )
    }
}
