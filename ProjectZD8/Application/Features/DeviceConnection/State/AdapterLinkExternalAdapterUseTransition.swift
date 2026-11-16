/// 常駐リンク以外の経路(手動接続)によるアダプター使用の開始・終了を、監視の状態と作用へ変換する純粋な遷移です。
///
/// ユーザー切断後の抑止中は、見張りの取り消し・再開を `AdapterLinkHeldWatchTransition` が扱います(この型は抑止中を変えません)。
///
/// 使用中に初期化・車両確認を始めない抑止は `AdapterLinkSupervisionConditions.isExternalAdapterUseActive` を参照する
/// リンク状態・前面復帰の遷移が担い、この型は開始・終了の瞬間の遷移だけを決めます。リンクは止めません。
nonisolated struct AdapterLinkExternalAdapterUseTransition: Sendable {
    /// 接続の置き換えで記録を終わらせる遷移(取り消し・通知取り下げ・理由付きの記録停止要求)です。
    private let recordingStop = AdapterLinkRecordingStopTransition()

    /// 手動接続がアダプターを使い始めたときの遷移を返します。
    ///
    /// 責務: 進行中の初期化・車両確認・検知を取り消して待機へ戻し、記録中なら手動接続による置き換え(`.superseded`)として記録停止を要求します。
    /// - Parameter state: 現在の監視状態。
    /// - Returns: 待機と抑止中は不変・作用なし。初期化・車両確認・検知済みは待機へ(取り消し・通知取り下げ)。
    ///   記録中は終了中へ(取り消し・通知取り下げ・記録停止要求)。終了中は終了中のまま(取り消し・通知取り下げ)。
    func began(from state: AdapterLinkSupervisionState) -> AdapterLinkSupervisionTransitionResult {
        guard state != .standby, !state.isHeldAfterUserStop else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        return recordingStop.stopped(from: state, reason: .superseded)
    }

    /// 手動接続がアダプターを使い終えたときの遷移を返します。
    ///
    /// 責務: 待機でリンクが `ready` なら、再接続や前面復帰を待たずにすぐ初期化からやり直します
    /// (アダプターは常時給電でリンクが `ready` のままのため、きっかけが他に無い)。それ以外の状態は変えません。
    /// - Parameters:
    ///   - state: 現在の監視状態。
    ///   - conditions: リンク状態・手動接続の使用状況・現在時刻を含む条件。
    /// - Returns: 待機・リンク `ready`・手動接続なしなら `initializing(linkReadyAt: now)` と初期化の作用。それ以外は状態不変・作用なし。
    func ended(
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
}
