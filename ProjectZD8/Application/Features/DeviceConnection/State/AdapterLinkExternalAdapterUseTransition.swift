/// 常駐リンク以外の経路(手動接続)によるアダプター使用の開始・終了を、監視の状態と作用へ変換する純粋な遷移です。
///
/// 使用中に初期化・車両確認を始めない抑止は `AdapterLinkSupervisionConditions.isExternalAdapterUseActive` を参照する
/// リンク状態・前面復帰の遷移が担い、この型は開始・終了の瞬間の遷移だけを決めます。リンクは止めません。
nonisolated struct AdapterLinkExternalAdapterUseTransition: Sendable {
    /// 常駐リンクの終了処理(取り消し・通知取り下げ・記録停止要求)です。
    private let lifecycle = AdapterLinkLifecycleTransition()

    /// 手動接続がアダプターを使い始めたときの遷移を返します。
    ///
    /// 責務: 進行中の初期化・車両確認・検知を取り消して待機へ戻し、記録中なら手動接続による置き換えとして記録停止を要求します。
    /// - Parameter state: 現在の監視状態。
    /// - Returns: 待機と抑止中は不変・作用なし。初期化・車両確認・検知済みは待機へ(取り消し・通知取り下げ)。
    ///   記録中は終了中へ(取り消し・通知取り下げ・記録停止要求)。終了中は終了中のまま(取り消し・通知取り下げ)。
    func began(from state: AdapterLinkSupervisionState) -> AdapterLinkSupervisionTransitionResult {
        guard state != .standby, state != .heldAfterUserStop else {
            return AdapterLinkSupervisionTransitionResult(state: state)
        }
        return lifecycle.tornDown(from: state)
    }

    /// 手動接続がアダプターを使い終えたときの遷移を返します。
    ///
    /// 責務: 状態を変えず作用も出しません。抑止の解除は条件側で行い、再確認は次の再接続か前面復帰から始めます。
    /// - Parameter state: 現在の監視状態。
    /// - Returns: 状態不変・作用なし。
    func ended(from state: AdapterLinkSupervisionState) -> AdapterLinkSupervisionTransitionResult {
        AdapterLinkSupervisionTransitionResult(state: state)
    }
}
