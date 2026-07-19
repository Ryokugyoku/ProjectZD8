import Foundation

/// システムのデバイス情報から検出したアダプター候補を表します。
struct DiscoveredAdapter: Equatable, Identifiable, Sendable {
    /// 同一候補を探索結果間で識別する安定識別子です。
    let id: String

    /// 候補を検出した物理接続方式です。
    let transportMode: AdapterTransportMode

    /// 一覧で優先表示する名称または代替識別子です。
    let displayName: String

    /// システムから取得できたメーカー名称です。
    let manufacturerName: String?

    /// システムから取得できた製品名称です。
    let productName: String?

    /// Bluetoothアドバタイズメントから取得できたローカル名称です。
    let advertisementLocalName: String?

    /// BluetoothアドバタイズメントにManufacturer Dataが含まれていたかどうかです。
    let hasManufacturerData: Bool?

    /// システムが候補へ割り当てた識別子です。
    let systemIdentifier: String

    /// システムから取得できたシリアル番号です。
    let serialNumber: String?

    /// システムから取得できたベンダー識別値です。
    let vendorIdentifier: String?

    /// システムから取得できた製品識別値です。
    let productIdentifier: String?

    /// 検出時点で接続済みと確認できたかどうかです。
    let isConnected: Bool

    /// 検出時点でシステムから取得できた接続状態です。
    let connectionState: DiscoveredAdapterConnectionState

    /// システム由来の各項目を保持するアダプター候補を生成します。
    ///
    /// 責務: 1件の検出結果を表示と後続設定に利用できる不変値へまとめます。
    /// - Parameters:
    ///   - id: 同一候補を識別する安定識別子。
    ///   - transportMode: 候補を検出した物理接続方式。
    ///   - displayName: 一覧で優先表示する名称または代替識別子。
    ///   - manufacturerName: システムから取得できたメーカー名称。
    ///   - productName: システムから取得できた製品名称。
    ///   - advertisementLocalName: Bluetoothアドバタイズメントから取得できたローカル名称。
    ///   - hasManufacturerData: BluetoothアドバタイズメントにManufacturer Dataが含まれていたかどうか。
    ///   - systemIdentifier: システムが候補へ割り当てた識別子。
    ///   - serialNumber: システムから取得できたシリアル番号。
    ///   - vendorIdentifier: システムから取得できたベンダー識別値。
    ///   - productIdentifier: システムから取得できた製品識別値。
    ///   - isConnected: 検出時点で接続済みと確認できたかどうか。
    ///   - connectionState: 検出時点でシステムから取得できた接続状態。省略時は `isConnected` から解決します。
    nonisolated init(
        id: String,
        transportMode: AdapterTransportMode,
        displayName: String,
        manufacturerName: String? = nil,
        productName: String? = nil,
        advertisementLocalName: String? = nil,
        hasManufacturerData: Bool? = nil,
        systemIdentifier: String,
        serialNumber: String? = nil,
        vendorIdentifier: String? = nil,
        productIdentifier: String? = nil,
        isConnected: Bool,
        connectionState: DiscoveredAdapterConnectionState? = nil
    ) {
        self.id = id
        self.transportMode = transportMode
        self.displayName = displayName
        self.manufacturerName = manufacturerName
        self.productName = productName
        self.advertisementLocalName = advertisementLocalName
        self.hasManufacturerData = hasManufacturerData
        self.systemIdentifier = systemIdentifier
        self.serialNumber = serialNumber
        self.vendorIdentifier = vendorIdentifier
        self.productIdentifier = productIdentifier
        self.isConnected = isConnected
        self.connectionState = connectionState ?? (isConnected ? .connected : .disconnected)
    }
}
