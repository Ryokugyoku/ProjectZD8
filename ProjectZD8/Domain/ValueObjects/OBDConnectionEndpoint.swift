import Foundation

/// OBDアダプターへ接続するためのフレームワーク非依存な物理終端です。
nonisolated struct OBDConnectionEndpoint: Equatable, Sendable {
    /// OBDアダプターまでの物理通信方式です。
    enum Transport: String, Equatable, Sendable {
        /// Bluetooth Low EnergyのUARTサービスを使用します。
        case bluetoothLowEnergy
        /// macOSから公開されたシリアルデバイスを使用します。
        case serial
    }

    /// 使用する物理通信方式です。
    let transport: Transport
    /// OSが接続対象へ割り当てた識別子です。
    let systemIdentifier: String
    /// ユーザーが識別できるアダプター名称です。
    let displayName: String

    /// 検出済みアダプターからOBD接続終端を生成します。
    ///
    /// 責務: 1件の検出結果を通信層へ渡せる最小接続情報へ変換します。
    /// - Parameter adapter: 接続対象として選択されたアダプター。
    init(adapter: DiscoveredAdapter) {
        transport = adapter.transportMode == .bluetooth ? .bluetoothLowEnergy : .serial
        systemIdentifier = adapter.systemIdentifier
        displayName = adapter.displayName
    }

    /// 永続化済み接続情報からOBD接続終端を生成します。
    ///
    /// 責務: 保存済み物理識別情報を変更せず接続終端へ固定します。
    /// - Parameters:
    ///   - transport: 使用する物理通信方式。
    ///   - systemIdentifier: OSが割り当てた接続先識別子。
    ///   - displayName: ユーザーが識別できる名称。
    init(transport: Transport, systemIdentifier: String, displayName: String) {
        self.transport = transport
        self.systemIdentifier = systemIdentifier
        self.displayName = displayName
    }
}
