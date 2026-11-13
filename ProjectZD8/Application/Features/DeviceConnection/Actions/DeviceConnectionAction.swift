/// アダプター探索と既定アダプターへの操作です。
nonisolated enum DeviceConnectionAction: Equatable, Sendable {
    /// 保存済みの既定アダプターを読み込みます。
    case defaultAdapterLoadRequested
    /// アダプターを探索します。探索中は無視します。
    case discoverRequested
    /// 実行中の探索を取り消します。取り消した探索の結果は捨てます。
    case discoveryCancelled
    /// 既定アダプターとして保存します。
    case defaultAdapterSelected(AdapterDescriptor)
    /// 既定アダプターを解除します。
    case defaultAdapterCleared
}
