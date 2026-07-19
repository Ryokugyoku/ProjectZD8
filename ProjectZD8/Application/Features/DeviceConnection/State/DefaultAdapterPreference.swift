/// 次回以降に優先するアダプターの永続化可能な識別情報です。
struct DefaultAdapterPreference: Equatable, Sendable {
    /// 探索結果間で同じ候補を識別する安定識別子です。
    let adapterID: String

    /// デフォルト候補を探索する物理接続方式です。
    let transportMode: AdapterTransportMode

    /// 設定済み候補として表示する名称です。
    let displayName: String

    /// システムが候補へ割り当てた識別子です。
    let systemIdentifier: String

    /// 保存済み値から通信層へ渡せるOBD物理終端です。
    var obdConnectionEndpoint: OBDConnectionEndpoint {
        OBDConnectionEndpoint(
            transport: transportMode == .bluetooth ? .bluetoothLowEnergy : .serial,
            systemIdentifier: systemIdentifier,
            displayName: displayName
        )
    }

    /// 検出済み候補からデフォルト設定を生成します。
    ///
    /// 責務: 1件の検出結果を次回探索で照合できるデフォルト設定へ変換します。
    /// - Parameter adapter: ユーザーがデフォルトとして確定した検出済み候補。
    init(adapter: DiscoveredAdapter) {
        adapterID = adapter.id
        transportMode = adapter.transportMode
        displayName = adapter.displayName
        systemIdentifier = adapter.systemIdentifier
    }

    /// 永続化済みの各値からデフォルト設定を復元します。
    ///
    /// 責務: 保存境界から読み込んだ識別情報をデフォルト設定へまとめます。
    /// - Parameters:
    ///   - adapterID: 探索結果間で同じ候補を識別する安定識別子。
    ///   - transportMode: デフォルト候補を探索する物理接続方式。
    ///   - displayName: 設定済み候補として表示する名称。
    ///   - systemIdentifier: システムが候補へ割り当てた識別子。
    init(
        adapterID: String,
        transportMode: AdapterTransportMode,
        displayName: String,
        systemIdentifier: String
    ) {
        self.adapterID = adapterID
        self.transportMode = transportMode
        self.displayName = displayName
        self.systemIdentifier = systemIdentifier
    }

    /// 検出済み候補がこのデフォルト設定と一致するかを返します。
    ///
    /// 責務: 1件の検出結果を保存済みの安定識別情報と照合します。
    /// - Parameter adapter: 照合対象の検出済み候補。
    /// - Returns: 同じ接続方式かつ同じ安定識別子を持つ場合は `true`。
    func matches(_ adapter: DiscoveredAdapter) -> Bool {
        transportMode == adapter.transportMode
            && adapterID == adapter.id
            && systemIdentifier == adapter.systemIdentifier
    }
}
