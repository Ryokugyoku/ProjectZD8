/// アダプター候補をシステムのデバイス情報から取得する境界です。
@MainActor
protocol AdapterDiscoveryPort {
    /// 指定された接続方式で現在参照できるアダプター候補を取得します。
    ///
    /// 責務: 1種類の接続方式に対応する現在のアダプター候補一覧を返します。
    /// - Parameter mode: 探索対象の物理接続方式。
    /// - Returns: システムから取得できたアダプター候補。
    /// - Throws: システムのデバイス情報へアクセスできない場合の探索エラー。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter]
}
