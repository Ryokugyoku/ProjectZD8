#if os(macOS)
import Foundation

/// macOSのUSB、Bluetooth Classic、BLE候補を1つの探索へ統合します。
nonisolated struct MacOSAdapterDiscovery: AdapterDiscoveryPort {
    /// USBシリアル候補の取得境界です。
    private let usbDiscovery: any AdapterDiscoveryPort
    /// Bluetooth Classic候補の取得境界です。
    private let classicDiscovery: any AdapterDiscoveryPort
    /// BLE候補の取得境界です。
    private let lowEnergyDiscovery: any AdapterDiscoveryPort

    /// 製品用の探索境界を生成します。
    ///
    /// 責務: 3種類のmacOS探索実装を1件の探索へ結合します。
    init() {
        self.init(
            usbDiscovery: MacOSUSBSerialAdapterDiscovery(),
            classicDiscovery: MacOSBluetoothClassicAdapterDiscovery(),
            lowEnergyDiscovery: AppleCoreBluetoothAdapterDiscovery()
        )
    }

    /// 3種類の探索境界を注入して生成します。
    ///
    /// 責務: 接続方式別の探索をテスト可能な境界へ固定します。
    init(
        usbDiscovery: any AdapterDiscoveryPort,
        classicDiscovery: any AdapterDiscoveryPort,
        lowEnergyDiscovery: any AdapterDiscoveryPort
    ) {
        self.usbDiscovery = usbDiscovery
        self.classicDiscovery = classicDiscovery
        self.lowEnergyDiscovery = lowEnergyDiscovery
    }

    /// 責務: 3方式を並行して探索し、識別子で重複を除いた候補を返します。
    /// - Throws: タスク取消し、または全方式が失敗した場合の探索エラー(BLE、Classic、USBの順に具体的な失敗を優先)。
    func discoverAdapters() async throws -> [AdapterDescriptor] {
        async let usb = outcome(of: usbDiscovery)
        async let classic = outcome(of: classicDiscovery)
        async let lowEnergy = outcome(of: lowEnergyDiscovery)
        let results = await [usb, classic, lowEnergy]
        try Task.checkCancellation()

        let succeeded = results.compactMap { try? $0.get() }
        guard !succeeded.isEmpty else {
            let failure = [results[2], results[1], results[0]].compactMap { result -> AdapterDiscoveryError? in
                if case let .failure(error) = result { return error as? AdapterDiscoveryError }
                return nil
            }.first
            throw failure ?? AdapterDiscoveryError.failed
        }
        return succeeded.flatMap { $0 }.uniquedByID()
    }

    /// 責務: 1つの探索境界の結果を、他方式から独立して扱える `Result` へ正規化します。
    private func outcome(of discovery: any AdapterDiscoveryPort) async -> Result<[AdapterDescriptor], any Error> {
        do {
            return .success(try await discovery.discoverAdapters())
        } catch {
            return .failure(error)
        }
    }
}
#endif
