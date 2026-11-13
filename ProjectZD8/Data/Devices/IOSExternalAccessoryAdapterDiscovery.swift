#if os(iOS)
@preconcurrency import ExternalAccessory
import Foundation

/// iOSが現在のアプリへ公開した接続済みExternalAccessory候補を取得します。
@MainActor
final class IOSExternalAccessoryAdapterDiscovery: AdapterDiscoveryPort {
    /// メーカー確認済みプロトコル許可集合です。
    private let configuration: IOSExternalAccessoryProtocolConfiguration
    /// 現在のExternalAccessory検出値を読み取る処理です。
    private let loadSnapshots: @MainActor () -> [IOSExternalAccessorySnapshot]
    /// フレームワーク検出値をDomain候補へ変換します。
    private let mapper = IOSExternalAccessorySnapshotMapper()

    /// 標準ExternalAccessoryマネージャーを使用する探索境界を生成します。
    ///
    /// 責務: Info.plist許可集合と現在接続一覧をiOS ExternalAccessory探索へ結び付けます。
    /// - Parameter configuration: メーカー確認済みプロトコル許可集合。
    convenience init(configuration: IOSExternalAccessoryProtocolConfiguration) {
        self.init(configuration: configuration) {
            EAAccessoryManager.shared().connectedAccessories.map(Self.makeSnapshot)
        }
    }

    /// テスト可能な検出値取得処理を注入して探索境界を生成します。
    ///
    /// 責務: ExternalAccessory候補変換を指定された検出値取得処理へ固定します。
    /// - Parameters:
    ///   - configuration: メーカー確認済みプロトコル許可集合。
    ///   - loadSnapshots: 現在のアクセサリー検出値を返す処理。
    init(
        configuration: IOSExternalAccessoryProtocolConfiguration,
        loadSnapshots: @escaping @MainActor () -> [IOSExternalAccessorySnapshot]
    ) {
        self.configuration = configuration
        self.loadSnapshots = loadSnapshots
    }

    /// 接続済みBluetooth Classicアクセサリー候補を返します。
    ///
    /// 責務: iOSがアプリへ公開したアクセサリーをプロトコル照合済み候補一覧へ変換します。
    /// - Parameter mode: 探索対象の物理接続方式。
    /// - Returns: 接続済みかつ許可プロトコルを公開するExternalAccessory候補。
    /// - Throws: Bluetooth以外が要求された場合は `AdapterDiscoveryError.transportUnsupported`。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        guard mode == .bluetooth else {
            throw AdapterDiscoveryError.transportUnsupported
        }
        return loadSnapshots().compactMap {
            mapper.makeAdapter(from: $0, configuration: configuration)
        }
    }

    /// フレームワークオブジェクトを並行処理可能な検出値へ変換します。
    ///
    /// 責務: 1件の `EAAccessory` から候補判定と再特定に必要な値だけを抽出します。
    /// - Parameter accessory: iOSが現在のアプリへ公開したアクセサリー。
    /// - Returns: フレームワーク参照を保持しない検出時スナップショット。
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
