#if os(iOS)
@preconcurrency import ExternalAccessory
import Foundation

/// iOSが現在のアプリへ公開した接続済みExternalAccessory候補を取得します。
nonisolated struct IOSExternalAccessoryAdapterDiscovery: AdapterDiscoveryPort {
    /// メーカー確認済みプロトコル許可集合です。
    private let configuration: IOSExternalAccessoryProtocolConfiguration
    /// 現在のExternalAccessory検出値を読み取る処理です。
    private let loadSnapshots: @MainActor @Sendable () -> [IOSExternalAccessorySnapshot]
    /// 検出値をアダプター記述へ変換します。
    private let mapper = IOSExternalAccessorySnapshotMapper()

    /// 標準ExternalAccessoryマネージャーを使う探索境界を生成します。
    ///
    /// 責務: Info.plist許可集合と現在接続一覧をExternalAccessory探索へ結び付けます。
    /// - Parameter configuration: メーカー確認済みプロトコル許可集合。
    init(configuration: IOSExternalAccessoryProtocolConfiguration) {
        self.init(configuration: configuration) {
            EAAccessoryManager.shared().connectedAccessories.map(Self.makeSnapshot)
        }
    }

    /// 検出値の取得処理を注入して探索境界を生成します。
    ///
    /// 責務: ExternalAccessory候補変換を指定された検出値取得処理へ固定します。
    init(
        configuration: IOSExternalAccessoryProtocolConfiguration,
        loadSnapshots: @escaping @MainActor @Sendable () -> [IOSExternalAccessorySnapshot]
    ) {
        self.configuration = configuration
        self.loadSnapshots = loadSnapshots
    }

    /// 責務: 接続済みで許可プロトコルを公開するアクセサリーをBluetooth Classic候補として返します。
    func discoverAdapters() async throws -> [AdapterDescriptor] {
        let snapshots = await loadSnapshots()
        return snapshots.compactMap { mapper.makeAdapter(from: $0, configuration: configuration) }
    }

    /// 責務: 1件の `EAAccessory` から候補判定と再特定に必要な値だけを抽出します。
    private static func makeSnapshot(from accessory: EAAccessory) -> IOSExternalAccessorySnapshot {
        IOSExternalAccessorySnapshot(
            connectionID: accessory.connectionID,
            name: accessory.name,
            manufacturer: accessory.manufacturer,
            modelNumber: accessory.modelNumber,
            serialNumber: accessory.serialNumber,
            protocolStrings: accessory.protocolStrings,
            isConnected: accessory.isConnected
        )
    }
}
#endif
