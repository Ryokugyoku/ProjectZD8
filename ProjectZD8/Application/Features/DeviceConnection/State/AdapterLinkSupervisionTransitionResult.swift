/// 常駐リンク監視の1回の遷移で決まった次の状態と、実行すべき作用の列です。
nonisolated struct AdapterLinkSupervisionTransitionResult: Equatable, Sendable {
    /// 遷移後の状態です。
    let state: AdapterLinkSupervisionState

    /// 状態を更新した後に順に実行する作用です。
    let effects: [AdapterLinkSupervisionEffect]

    /// 次の状態と作用の列を固定して生成します。
    ///
    /// 責務: 1回の遷移結果を不変値へまとめます。
    /// - Parameters:
    ///   - state: 遷移後の状態。
    ///   - effects: 順に実行する作用。
    init(state: AdapterLinkSupervisionState, effects: [AdapterLinkSupervisionEffect] = []) {
        self.state = state
        self.effects = effects
    }
}
