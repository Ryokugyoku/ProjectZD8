/// この端末から接続できる実アダプターを探索する契約です。デモ用アダプターは含みません。
nonisolated protocol AdapterDiscoveryPort: Sendable {
    /// 責務: 現在見つかるアダプターを1回探索して返します。
    /// - Throws: 探索できない場合の `AdapterDiscoveryError`。
    func discoverAdapters() async throws -> [AdapterDescriptor]
}

/// アダプター探索の失敗です。
nonisolated enum AdapterDiscoveryError: Error, Equatable, Sendable {
    case bluetoothPoweredOff
    case bluetoothUnauthorized
    case bluetoothUnsupported
    case failed
}
