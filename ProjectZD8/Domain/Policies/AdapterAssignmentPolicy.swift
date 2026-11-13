/// 物理アダプターを接続役割へ割り当てる際の競合規則です。
struct AdapterAssignmentPolicy {
    /// 候補が割当先以外の接続役割で使用済みかを判定します。
    ///
    /// 責務: 1件の候補について同じ安定識別子を複数の接続役割へ割り当てる競合を検出します。
    /// - Parameters:
    ///   - adapter: 新たに割り当てるアダプター候補。
    ///   - role: 候補を割り当てる接続役割。
    ///   - assignments: 現在の接続役割別割当。
    /// - Returns: 同じ候補が割り当て済みの別接続役割。競合しない場合は `nil`。
    static func conflictingRole(
        for adapter: DiscoveredAdapter,
        assigningTo role: AdapterConnectionRole,
        assignments: [AdapterConnectionRole: DiscoveredAdapter]
    ) -> AdapterConnectionRole? {
        assignments.first {
            $0.key != role && $0.value.id == adapter.id
        }?.key
    }
}
