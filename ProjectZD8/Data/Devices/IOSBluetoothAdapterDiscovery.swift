#if os(iOS)
/// iOSのBluetooth Classic接続一覧とBluetooth Low Energyスキャンを統合します。
@MainActor
final class IOSBluetoothAdapterDiscovery: AdapterDiscoveryPort {
    /// 接続済みExternalAccessory候補の取得境界です。
    private let externalAccessoryDiscovery: any AdapterDiscoveryPort
    /// 周辺Bluetooth Low Energy候補のスキャン境界です。
    private let lowEnergyDiscovery: any AdapterDiscoveryPort

    /// 製品用のBluetooth探索境界を生成します。
    ///
    /// 責務: ExternalAccessoryとCoreBluetoothの探索実装を1件のiOS Bluetooth探索へ結合します。
    /// - Parameter externalAccessoryConfiguration: メーカー確認済みExternalAccessoryプロトコル許可集合。
    convenience init(externalAccessoryConfiguration: IOSExternalAccessoryProtocolConfiguration) {
        self.init(
            externalAccessoryDiscovery: IOSExternalAccessoryAdapterDiscovery(
                configuration: externalAccessoryConfiguration
            ),
            lowEnergyDiscovery: AppleCoreBluetoothAdapterDiscovery()
        )
    }

    /// 2種類のBluetooth探索境界を注入して生成します。
    ///
    /// 責務: Bluetooth ClassicとLow Energyの候補取得順序をテスト可能な境界へ固定します。
    /// - Parameters:
    ///   - externalAccessoryDiscovery: 接続済みExternalAccessory候補の取得境界。
    ///   - lowEnergyDiscovery: 周辺Bluetooth Low Energy候補のスキャン境界。
    init(
        externalAccessoryDiscovery: any AdapterDiscoveryPort,
        lowEnergyDiscovery: any AdapterDiscoveryPort
    ) {
        self.externalAccessoryDiscovery = externalAccessoryDiscovery
        self.lowEnergyDiscovery = lowEnergyDiscovery
    }

    /// Bluetooth Classic接続一覧とLow Energyスキャン結果を重複なく返します。
    ///
    /// 責務: 1回のBluetooth探索要求を2種類のiOS Bluetooth候補へ統合します。
    /// - Parameter mode: 探索対象の物理接続方式。
    /// - Returns: ExternalAccessoryを優先し識別子で重複を除いた候補一覧。
    /// - Throws: Bluetooth以外、または候補を取得できない状態での下位探索エラー。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        guard mode == .bluetooth else {
            throw AdapterDiscoveryError.transportUnsupported
        }
        let externalAccessories = try await externalAccessoryDiscovery.discoverAdapters(for: mode)
        do {
            let lowEnergyAdapters = try await lowEnergyDiscovery.discoverAdapters(for: mode)
            return unique(externalAccessories + lowEnergyAdapters)
        } catch where !externalAccessories.isEmpty {
            return externalAccessories
        }
    }

    /// 識別子が重複する探索候補を先着優先で除外します。
    ///
    /// 責務: 複数Bluetooth境界の候補列を1件の識別子につき最初の候補へ縮約します。
    /// - Parameter adapters: 統合前の探索候補列。
    /// - Returns: 入力順を維持した重複なし候補列。
    private func unique(_ adapters: [DiscoveredAdapter]) -> [DiscoveredAdapter] {
        var identifiers: Set<String> = []
        return adapters.filter { identifiers.insert($0.id).inserted }
    }
}
#endif
