/// アダプター探索と既定アダプターの表示状態です。
nonisolated struct DeviceConnectionState: Equatable, Sendable {
    /// 探索の進行状態です。
    nonisolated enum Discovery: Equatable, Sendable {
        /// まだ探索していません(または取り消しました)。
        case idle
        /// 探索中です。
        case discovering
        /// 探索が完了しました。
        case completed
        /// 探索に失敗しました。
        case failed(AdapterDiscoveryError)
    }

    var discovery: Discovery = .idle
    /// 直近の探索で見つかったアダプターです。デモモード中は末尾に模擬アダプターを含みます。
    var adapters: [AdapterDescriptor] = []
    /// 保存済みの既定アダプターです。
    var defaultAdapter: AdapterDescriptor?
    /// 直近の探索結果に既定アダプターが含まれるかどうかです。探索が完了するまでは `false` です。
    var isDefaultAdapterDetected = false

    /// 責務: 初期状態を生成します。
    init() {}
}
