#if os(iOS)
/// iOSアプリケーションで使用する実装依存関係を組み立てます。
@MainActor
enum IOSApplicationComposition {
    /// 実CoreBluetooth探索を注入した設定プレゼンテーションモデルを生成します。
    ///
    /// 責務: iOSのCoreBluetooth探索実装をDeviceConnectionユースケースと設定表示境界へ結び付けます。
    /// - Returns: 実際のBLE探索を使用するiOS設定プレゼンテーションモデル。
    static func makeSettingsPresentationModel() -> IOSSettingsPresentationModel {
        let discovery = IOSCoreBluetoothAdapterDiscovery()
        let discoverAdapters = DiscoverAdaptersUseCase(discoveryPort: discovery)
        let latestDiscovery = LatestAdapterDiscoveryUseCase(discoverAdapters: discoverAdapters)
        return IOSSettingsPresentationModel(
            state: IOSSettingsState(),
            latestDiscovery: latestDiscovery
        )
    }
}
#endif
