#if os(macOS)
/// macOSのUSB、Bluetooth Classic、Bluetooth Low Energy候補を1つの探索境界へ統合します。
@MainActor
final class MacOSAdapterDiscovery: AdapterDiscoveryPort {
    /// USBとBluetooth Classicを取得するmacOSシステム探索境界です。
    private let systemDiscovery: any AdapterDiscoveryPort

    /// iPhoneと同じCoreBluetooth処理でBLE候補を取得する探索境界です。
    private let lowEnergyDiscovery: any AdapterDiscoveryPort

    /// macOS固有探索と共通BLE探索を注入して生成します。
    ///
    /// 責務: 2種類のmacOS探索境界を接続方式別に利用できる状態へ固定します。
    /// - Parameters:
    ///   - systemDiscovery: USBとBluetooth Classicを取得する探索境界。
    ///   - lowEnergyDiscovery: CoreBluetoothでBLE候補を取得する探索境界。
    init(
        systemDiscovery: any AdapterDiscoveryPort,
        lowEnergyDiscovery: any AdapterDiscoveryPort
    ) {
        self.systemDiscovery = systemDiscovery
        self.lowEnergyDiscovery = lowEnergyDiscovery
    }

    /// USBは既存システム探索へ渡し、BluetoothはClassicとBLEを並行取得します。
    ///
    /// 責務: 1回のmacOS探索要求を物理方式に対応する候補集合へ変換します。
    /// - Parameter mode: 探索対象の物理接続方式。
    /// - Returns: USB候補、または識別子で重複を除いたClassicとBLEの候補。
    /// - Throws: タスク取消し、またはBluetooth探索を両方とも開始・完了できない場合の探索エラー。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        guard mode == .bluetooth else {
            return try await systemDiscovery.discoverAdapters(for: mode)
        }

        async let systemCandidates = candidates(from: systemDiscovery, mode: mode)
        async let lowEnergyCandidates = candidates(from: lowEnergyDiscovery, mode: mode)
        let (systemResult, lowEnergyResult) = await (systemCandidates, lowEnergyCandidates)
        try Task.checkCancellation()

        guard systemResult != nil || lowEnergyResult != nil else {
            throw AdapterDiscoveryError.bluetoothStateUnavailable
        }
        return unique((systemResult ?? []) + (lowEnergyResult ?? []))
    }

    /// 1つの探索境界を候補または利用不能へ正規化します。
    ///
    /// 責務: 一方のBluetooth方式の失敗を他方の成功から独立して扱える任意候補へ変換します。
    /// - Parameters:
    ///   - discovery: 候補を取得する探索境界。
    ///   - mode: 探索対象の物理接続方式。
    /// - Returns: 探索に成功した候補。失敗した場合は `nil`。
    private func candidates(
        from discovery: any AdapterDiscoveryPort,
        mode: AdapterTransportMode
    ) async -> [DiscoveredAdapter]? {
        try? await discovery.discoverAdapters(for: mode)
    }

    /// 複数方式から同じ識別子で届いた候補を先着優先で除外します。
    ///
    /// 責務: 1件の候補列を識別子ごとの初出候補へ縮約します。
    /// - Parameter adapters: 重複除外前の候補列。
    /// - Returns: 入力順を維持した重複なし候補列。
    private func unique(_ adapters: [DiscoveredAdapter]) -> [DiscoveredAdapter] {
        var identifiers: Set<String> = []
        return adapters.filter { identifiers.insert($0.id).inserted }
    }
}
#endif
