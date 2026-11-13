#if os(iOS)
import Foundation

/// iOSのBluetooth Classic接続一覧(ExternalAccessory)とBLEスキャンを統合します。
nonisolated struct IOSAdapterDiscovery: AdapterDiscoveryPort {
    /// 接続済みExternalAccessory候補の取得境界です。
    private let externalAccessoryDiscovery: any AdapterDiscoveryPort
    /// 周辺BLE候補のスキャン境界です。
    private let lowEnergyDiscovery: any AdapterDiscoveryPort

    /// 製品用の探索境界を生成します。
    ///
    /// 責務: ExternalAccessoryとCoreBluetoothの探索実装を1件のiOS探索へ結合します。
    /// - Parameter externalAccessoryConfiguration: メーカー確認済みプロトコル許可集合。
    init(externalAccessoryConfiguration: IOSExternalAccessoryProtocolConfiguration) {
        self.init(
            externalAccessoryDiscovery: IOSExternalAccessoryAdapterDiscovery(
                configuration: externalAccessoryConfiguration
            ),
            lowEnergyDiscovery: AppleCoreBluetoothAdapterDiscovery()
        )
    }

    /// 2種類の探索境界を注入して生成します。
    ///
    /// 責務: Bluetooth ClassicとBLEの候補取得順序をテスト可能な境界へ固定します。
    init(
        externalAccessoryDiscovery: any AdapterDiscoveryPort,
        lowEnergyDiscovery: any AdapterDiscoveryPort
    ) {
        self.externalAccessoryDiscovery = externalAccessoryDiscovery
        self.lowEnergyDiscovery = lowEnergyDiscovery
    }

    /// 責務: ExternalAccessoryを優先し、識別子で重複を除いた候補を返します。
    /// - Throws: ExternalAccessoryの探索失敗、またはClassic候補が無い状態でのBLE探索失敗。
    func discoverAdapters() async throws -> [AdapterDescriptor] {
        let externalAccessories = try await externalAccessoryDiscovery.discoverAdapters()
        do {
            let lowEnergyAdapters = try await lowEnergyDiscovery.discoverAdapters()
            return (externalAccessories + lowEnergyAdapters).uniquedByID()
        } catch where !externalAccessories.isEmpty && !(error is CancellationError) {
            return externalAccessories
        }
    }
}
#endif
