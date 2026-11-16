import Foundation

/// アダプター初期化から車両検知までと、前面復帰による再開を決める純粋な遷移です。
///
/// 確認は応答駆動です。確認の結果を受け取ったことを次の確認の起点にし、固定の待機を挟みません。無応答の間の頻度は
/// アダプター側の最大タイムアウト(`ATSTFF`)で決まります。結果が最短間隔より早く返った時だけ残り時間を待ちます
/// (`AdapterLinkVehicleConfirmationPacing`)。窓と回数の上限は結果を受け取るたびに判定し(`AdapterLinkVehicleConfirmationWindowPolicy`)、
/// アプリが前面にいる間は窓切れで休止せず窓を取り直します。
nonisolated struct AdapterLinkVehicleConfirmationTransition: Sendable {
    /// 確認窓と最短間隔の定数です。
    let timing: AdapterLinkSupervisionTiming

    /// 窓と回数の上限の判定です。
    private let windowPolicy: AdapterLinkVehicleConfirmationWindowPolicy

    /// 最短間隔の判定です。
    private let pacing: AdapterLinkVehicleConfirmationPacing

    /// 確認窓と最短間隔を固定して生成します。
    ///
    /// 責務: 車両確認の時間定数を遷移と判定へ結び付けます。
    /// - Parameter timing: 確認窓と最短間隔。
    init(timing: AdapterLinkSupervisionTiming) {
        self.timing = timing
        windowPolicy = AdapterLinkVehicleConfirmationWindowPolicy(timing: timing)
        pacing = AdapterLinkVehicleConfirmationPacing(minimumInterval: timing.vehicleConfirmationInterval)
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
    /// 責務: 低頻度確認中であれば、応答ありを検知へ、無応答を次の確認(応答駆動。最短間隔より早ければ残り時間の待機)か
    /// 窓の取り直しか休止へ変換します。
    /// - Parameters:
    ///   - outcome: ECU応答の有無。
    ///   - state: 現在の監視状態。
    ///   - conditions: 結果を受け取った時刻・前面かどうか・最後に確認を送った時刻を含む条件。
    /// - Returns: 次の状態と作用。低頻度確認中以外では何もしません。
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
            let decision = windowPolicy.decision(for: confirmation, now: conditions.now, isForeground: conditions.isForeground)
            guard decision != .pause else {
                return AdapterLinkSupervisionTransitionResult(state: .confirmingVehicle(paused(confirmation)))
            }
            guard let wait = pacing.remainingWait(sentAt: conditions.lastVehicleConfirmationSentAt, now: conditions.now) else {
                return confirmAgain(confirmation, decision: decision, now: conditions.now)
            }
            return AdapterLinkSupervisionTransitionResult(
                state: .confirmingVehicle(confirmation),
                effects: [.scheduleVehicleConfirmation(after: wait)]
            )
        }
    }

    /// 最短間隔の残り時間の待機が終わったときの遷移を返します。
    ///
    /// 責務: 低頻度確認中であれば、窓と回数の上限を判定し直して、最大タイムアウトで次の確認を送るか、窓を取り直すか、休止します。
    /// 待ち明けの後に最短間隔を測り直して待ち直すことはしません。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - conditions: 待ち明けの時刻と前面かどうかを含む条件。
    /// - Returns: 次の状態と作用。低頻度確認中以外では何もしません。
    func vehicleConfirmationIntervalElapsed(
        from state: AdapterLinkSupervisionState,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard case let .confirmingVehicle(confirmation) = state, confirmation.phase == .probing else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        let decision = windowPolicy.decision(for: confirmation, now: conditions.now, isForeground: conditions.isForeground)
        guard decision != .pause else {
            return AdapterLinkSupervisionTransitionResult(state: .confirmingVehicle(paused(confirmation)))
        }
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
            return AdapterLinkSupervisionTransitionResult(
                state: .initializing(linkReadyAt: conditions.now),
                effects: [.initializeAdapter]
            )
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
    /// 責務: 窓の判定が続行なら回数を1増やし、取り直し(前面での窓切れ・回数の上限)なら窓と回数を取り直してから、
    /// `.adapterMaximum` の確認を要求します。休止の判定は呼び出し側が済ませている前提です。
    /// - Parameters:
    ///   - confirmation: 現在の確認進行状況。
    ///   - decision: 窓と回数の判定結果(休止以外)。
    ///   - now: 現在時刻。取り直す窓の起点です。
    /// - Returns: 確認中への遷移と確認の作用。
    private func confirmAgain(
        _ confirmation: AdapterLinkVehicleConfirmation,
        decision: AdapterLinkVehicleConfirmationWindowDecision,
        now: Date
    ) -> AdapterLinkSupervisionTransitionResult {
        let next: AdapterLinkVehicleConfirmation
        if decision == .continueInWindow {
            next = AdapterLinkVehicleConfirmation(
                adapterProbeEvidence: confirmation.adapterProbeEvidence,
                windowEndsAt: confirmation.windowEndsAt,
                attemptCount: confirmation.attemptCount + 1,
                phase: .probing
            )
        } else {
            next = windowPolicy.renewed(confirmation, at: now)
        }
        return AdapterLinkSupervisionTransitionResult(state: .confirmingVehicle(next), effects: [.confirmVehicle(.adapterMaximum)])
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
