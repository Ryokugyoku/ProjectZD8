/// 探索で見つかった、または既定として保存したOBDアダプターを表します。
nonisolated struct AdapterDescriptor: Identifiable, Hashable, Codable, Sendable {
    /// 通信経路です。
    let transport: AdapterTransport
    /// OSが接続に使う識別値です(BLEのPeripheral UUID、デバイスパス、Bluetoothアドレスなど)。
    let systemIdentifier: String
    /// 画面に表示する名称です。
    let displayName: String
    /// メーカー名や製品名などの補足表示です。
    let detail: String?

    /// 通信経路とOS識別値から導出する安定IDです。
    var id: String { "\(transport.rawValue):\(systemIdentifier)" }

    /// アダプター記述を生成します。
    ///
    /// 責務: 接続に必要な最小情報を1件にまとめます。
    init(transport: AdapterTransport, systemIdentifier: String, displayName: String, detail: String? = nil) {
        self.transport = transport
        self.systemIdentifier = systemIdentifier
        self.displayName = displayName
        self.detail = detail
    }
}
