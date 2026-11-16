import Foundation

/// ユーザー切断後の抑止中に、ECU がまだ応答しているか(同じ走行が続いているか)を見張る純粋な遷移です。
///
/// 見張りは応答駆動です。`.heldWatch` の確認(`ATAT0` + `ATSTFF` + `0100`)は ECU が応答してもアダプターの
/// タイムアウト満了まで待つので、結果の受信を次の確認の起点にするだけで約1秒周期になります(実アダプターでは未検証)。
/// `ATAT0` を受け付けないアダプターで結果が早く返っても、最短間隔の待ち(`AdapterLinkVehicleConfirmationPacing`)で空回りしません。
/// 無応答が連続2回なら走行の終わりとみなし、抑止を解いて初期化からやり直します(窓は解いた時刻から)。
/// 見張りは抑止に入ってから(または前面復帰で取り直してから)上限の時間を超えたらやめ(ちょうどは続ける)、従来の抑止へ戻ります。
/// 手動接続が使い始めたら進行中の見張りの確認を取り消し、使っている間は新しい確認を送らず抑止も解きません。
/// 使い終えたらリンクが `ready` なら見張りを再開します(上限はそのまま)。見張りの開始待ちで使い終えたら、その時刻から見張りを始めます。
/// 確認の失敗は無応答として数えません。リンク待ちの保持(`awaitingLink`)の間は何も送らず、リンクの復帰は
/// `AdapterLinkHeldLinkWaitTransition` が扱います。
nonisolated struct AdapterLinkHeldWatchTransition: Sendable {
    /// 走行の終わりとみなす連続無応答の回数です。
    static let consecutiveNoResponsesToRelease = 2

    /// 見張りの上限と最短間隔の定数です。
    let timing: AdapterLinkSupervisionTiming

    /// 最短間隔の判定です。
    private let pacing: AdapterLinkVehicleConfirmationPacing

    /// 時間定数を固定して生成します。
    ///
    /// 責務: 見張りの上限と最短間隔を遷移へ結び付けます。
    /// - Parameter timing: 見張りの上限と最短間隔。
    init(timing: AdapterLinkSupervisionTiming) {
        self.timing = timing
        pacing = AdapterLinkVehicleConfirmationPacing(minimumInterval: timing.vehicleConfirmationInterval)
    }

    /// 記録の終了通知を受けた後に、見張りを始める遷移を返します。
    ///
    /// 責務: 開始待ちの抑止で、リンクが `ready` かつ手動接続が使っていなければ、上限を設けて最初の見張りの確認を送ります。
    /// - Parameters:
    ///   - watch: 現在の見張りの進行状況。
    ///   - conditions: リンク状態と現在時刻を含む条件。
    /// - Returns: 次の状態と作用。開始待ち以外と、始められない条件では何もしません。
    func recordingEndSettled(
        _ watch: AdapterLinkHeldWatch,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard watch.phase == .awaitingStart, canSend(conditions) else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch))
        }
        return started(watch, conditions: conditions)
    }

    /// 抑止中の前面復帰に対する遷移を返します。
    ///
    /// 責務: 見張り中なら上限だけを取り直し(確認は重複させない)、開始待ち・停止中なら上限を設けて見張りを直ちに再開します。
    /// リンク待ちの保持では何もしません(リンクの復帰を待つため)。
    /// - Parameters:
    ///   - watch: 現在の見張りの進行状況。
    ///   - conditions: リンク状態と現在時刻を含む条件。
    /// - Returns: 抑止のままの遷移。検知・記録開始はしません。
    func appDidBecomeActive(
        _ watch: AdapterLinkHeldWatch,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard canSend(conditions), !isAwaitingLink(watch) else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch))
        }
        if case .watching = watch.phase {
            let extended = AdapterLinkHeldWatch(consecutiveNoResponses: watch.consecutiveNoResponses, phase: watchingPhase(from: conditions.now))
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(extended))
        }
        return started(watch, conditions: conditions)
    }

    /// 見張りの確認の結果に対する遷移を返します。
    ///
    /// 責務: 応答で連続無応答の回数を0へ戻し、無応答で数えて連続2回なら抑止を解いて初期化からやり直します。
    /// それ以外は、見張り中なら次の確認(早すぎれば残り時間の待機)を送り、上限を過ぎていれば見張りをやめます。
    /// リンク待ち・停止中(見張りの確認を送っていない段階)に遅れて届いた結果は数えず、状態を変えません
    /// (数えるとリンク復帰後・再開後の見張りが無応答1回で解けてしまうため)。開始待ちでは従来どおり数えます(U3 受け入れ条件 10)。
    /// - Parameters:
    ///   - outcome: ECU応答の有無。
    ///   - watch: 現在の見張りの進行状況。
    ///   - conditions: 結果を受け取った時刻と最後に確認を送った時刻を含む条件。
    /// - Returns: 次の状態と作用。
    func confirmationCompleted(
        _ outcome: VehicleResponseOutcome,
        watch: AdapterLinkHeldWatch,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard countsConfirmationResults(watch) else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch))
        }
        let count = outcome == .noResponse ? watch.consecutiveNoResponses + 1 : 0
        if count >= Self.consecutiveNoResponsesToRelease, !conditions.isExternalAdapterUseActive {
            return AdapterLinkSupervisionTransitionResult(state: .initializing(linkReadyAt: conditions.now), effects: [.initializeAdapter])
        }
        return continued(AdapterLinkHeldWatch(consecutiveNoResponses: count, phase: watch.phase), conditions: conditions)
    }

    /// 見張りの確認が失敗した(応答の有無を判定できなかった)ときの遷移を返します。
    ///
    /// 責務: 無応答とは数えず連続無応答の回数を保ったまま、見張り中なら次の確認を送ります(走行の終わりを誤って判定しないため)。
    /// リンク待ち・停止中に遅れて届いた失敗では状態を変えません。
    /// - Parameters:
    ///   - watch: 現在の見張りの進行状況。
    ///   - conditions: 結果を受け取った時刻と最後に確認を送った時刻を含む条件。
    /// - Returns: 抑止のままの遷移。
    func confirmationFailed(
        _ watch: AdapterLinkHeldWatch,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard countsConfirmationResults(watch) else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch))
        }
        return continued(watch, conditions: conditions)
    }

    /// 最短間隔の残り時間の待機が終わったときの遷移を返します。
    ///
    /// 責務: 見張り中で上限の内なら次の見張りの確認を送り、上限を過ぎていれば見張りをやめます。
    /// - Parameters:
    ///   - watch: 現在の見張りの進行状況。
    ///   - conditions: 待ち明けの時刻を含む条件。
    /// - Returns: 抑止のままの遷移。
    func intervalElapsed(
        _ watch: AdapterLinkHeldWatch,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard isWatching(watch, now: conditions.now) else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(stoppedIfExpired(watch, now: conditions.now)))
        }
        guard canSend(conditions) else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch))
        }
        return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch), effects: [.confirmVehicle(.heldWatch)])
    }

    /// 抑止中に手動接続がアダプターを使い始めたときの遷移を返します。
    ///
    /// 責務: 見張り中なら進行中の見張りの確認を取り消します(手動接続とバイトストリームを取り合わないため)。状態は変えません。
    /// - Parameter watch: 現在の見張りの進行状況。
    /// - Returns: 見張り中なら `[.cancelOperations]`、それ以外は作用なし。
    func externalAdapterUseBegan(_ watch: AdapterLinkHeldWatch) -> AdapterLinkSupervisionTransitionResult {
        guard case .watching = watch.phase else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch))
        }
        return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch), effects: [.cancelOperations])
    }

    /// 抑止中に手動接続がアダプターを使い終えたときの遷移を返します。
    ///
    /// 責務: 見張り中で、上限を超えておらず、リンクが `ready` なら、前面復帰を待たずに見張りの確認を再開します。
    /// 上限は保持に入った(または前面復帰で取り直した)時点からのままにします。上限を超えていれば見張りをやめます。
    /// 見張りの開始待ち(記録の終了時点で手動接続が使用中だった)で、リンクが `ready` なら、この時刻から上限を設けて見張りを始めます。
    /// - Parameters:
    ///   - watch: 現在の見張りの進行状況。
    ///   - conditions: リンク状態と現在時刻を含む条件。
    /// - Returns: 抑止のままの遷移。
    func externalAdapterUseEnded(
        _ watch: AdapterLinkHeldWatch,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        if watch.phase == .awaitingStart, canSend(conditions) {
            return started(watch, conditions: conditions)
        }
        guard case .watching = watch.phase else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch))
        }
        guard isWatching(watch, now: conditions.now) else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(stoppedIfExpired(watch, now: conditions.now)))
        }
        guard canSend(conditions) else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch))
        }
        return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch), effects: [.confirmVehicle(.heldWatch)])
    }

    /// リンク待ちの保持で、同じ走行とみなす上限以内にリンクが `ready` へ戻った時の遷移を返します。
    ///
    /// 責務: 手動接続が使っていなければ、リンクの復帰の時刻から上限を設けて見張りを始めます。
    /// 使っている間は見張りの開始待ちにして、使い終えた時に始めさせます。直前のリンク状態は見ません(復帰の入力そのものなので)。
    /// - Parameters:
    ///   - watch: 現在の見張りの進行状況。
    ///   - conditions: 復帰の時刻と手動接続の使用中かどうかを含む条件。
    /// - Returns: 抑止のままの遷移。
    func linkReturned(
        _ watch: AdapterLinkHeldWatch,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard !conditions.isExternalAdapterUseActive else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(.awaitingStart))
        }
        return started(watch, conditions: conditions)
    }

    /// 結果を反映した見張りを、上限と送信の可否に応じて続ける遷移を返します。
    ///
    /// 責務: 見張り中で上限の内なら次の確認(早すぎれば残り時間の待機)を送り、上限を過ぎていれば見張りをやめます。
    /// - Parameters:
    ///   - watch: 結果を反映した見張りの進行状況。
    ///   - conditions: 結果を受け取った時刻と最後に確認を送った時刻を含む条件。
    /// - Returns: 抑止のままの遷移。
    private func continued(
        _ watch: AdapterLinkHeldWatch,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        guard isWatching(watch, now: conditions.now) else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(stoppedIfExpired(watch, now: conditions.now)))
        }
        guard canSend(conditions) else {
            return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch))
        }
        let effect = pacing.nextEffect(timeout: .heldWatch, sentAt: conditions.lastVehicleConfirmationSentAt, now: conditions.now)
        return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watch), effects: [effect])
    }

    /// 上限を設けて見張りを始める遷移を返します。
    ///
    /// 責務: 連続無応答の回数を保ったまま、`now` + 上限まで見張り中にし、見張りの確認を1回送ります。
    /// - Parameters:
    ///   - watch: 現在の見張りの進行状況。
    ///   - conditions: 現在時刻を含む条件。
    /// - Returns: 見張り中への遷移と確認の作用。
    private func started(
        _ watch: AdapterLinkHeldWatch,
        conditions: AdapterLinkSupervisionConditions
    ) -> AdapterLinkSupervisionTransitionResult {
        let watching = AdapterLinkHeldWatch(consecutiveNoResponses: watch.consecutiveNoResponses, phase: watchingPhase(from: conditions.now))
        return AdapterLinkSupervisionTransitionResult(state: .heldAfterUserStop(watching), effects: [.confirmVehicle(.heldWatch)])
    }

    /// 指定した時刻から上限までの見張り中の段階を返します。
    ///
    /// 責務: 見張りの終了時刻を `now` + 上限にします。
    /// - Parameter now: 見張りの起点。
    /// - Returns: 見張り中の段階。
    private func watchingPhase(from now: Date) -> AdapterLinkHeldWatchPhase {
        .watching(endsAt: now.addingTimeInterval(timing.heldWatchLimit))
    }

    /// 見張り中で、上限の内かどうかを返します。
    ///
    /// 責務: 見張り中の段階で、終了時刻を超えていないことを判定します(ちょうど上限の時刻は見張りを続けます)。
    /// - Parameters:
    ///   - watch: 見張りの進行状況。
    ///   - now: 判定する時刻。
    /// - Returns: 見張りを続けるなら `true`。
    private func isWatching(_ watch: AdapterLinkHeldWatch, now: Date) -> Bool {
        guard case let .watching(endsAt) = watch.phase else { return false }
        return now <= endsAt
    }

    /// 上限を過ぎた見張りを停止へ移した値を返します。
    ///
    /// 責務: 見張り中で上限を過ぎていれば段階を停止にし、それ以外(開始待ち・停止中)はそのまま返します。
    /// - Parameters:
    ///   - watch: 見張りの進行状況。
    ///   - now: 判定する時刻。
    /// - Returns: 必要なら停止へ移した見張りの進行状況。
    private func stoppedIfExpired(_ watch: AdapterLinkHeldWatch, now: Date) -> AdapterLinkHeldWatch {
        guard case .watching = watch.phase else { return watch }
        return AdapterLinkHeldWatch(consecutiveNoResponses: watch.consecutiveNoResponses, phase: .stopped)
    }

    /// 確認の結果を見張りへ反映する段階かどうかを返します。
    ///
    /// 責務: 見張り中(上限の内外は問わない)と開始待ちを `true`、リンク待ち・停止中を `false` にします。
    /// - Parameter watch: 見張りの進行状況。
    /// - Returns: 結果を数える段階なら `true`。
    private func countsConfirmationResults(_ watch: AdapterLinkHeldWatch) -> Bool {
        switch watch.phase {
        case .watching, .awaitingStart: true
        case .awaitingLink, .stopped: false
        }
    }

    /// リンク待ちの保持かどうかを返します。
    ///
    /// 責務: 見張りの段階がリンクの復帰待ちであることを判定します。
    /// - Parameter watch: 見張りの進行状況。
    /// - Returns: リンク待ちの保持なら `true`。
    private func isAwaitingLink(_ watch: AdapterLinkHeldWatch) -> Bool {
        if case .awaitingLink = watch.phase { return true }
        return false
    }

    /// 見張りの確認をアダプターへ送ってよいかどうかを返します。
    ///
    /// 責務: リンクが `ready` で、手動接続がアダプターを使っていないことを判定します。
    /// - Parameter conditions: リンク状態と手動接続の使用中かどうかを含む条件。
    /// - Returns: 送ってよいなら `true`。
    private func canSend(_ conditions: AdapterLinkSupervisionConditions) -> Bool {
        conditions.isLinkReady && !conditions.isExternalAdapterUseActive
    }
}
