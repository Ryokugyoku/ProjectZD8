/// 既定アダプターをこの端末に保存する契約です。
nonisolated protocol DefaultAdapterStorePort: Sendable {
    /// 責務: 保存済みの既定アダプターを返します。未設定なら `nil` を返します。
    func load() -> AdapterDescriptor?
    /// 責務: 既定アダプターを保存します。`nil` で解除します。
    func save(_ adapter: AdapterDescriptor?)
}
