import Foundation

/// 接続終端に対して、常駐リンク上のトランスポートを使うか従来のトランスポートを使うかを決める純粋な方針です。
nonisolated struct AdapterLinkTransportSelectionPolicy: Sendable {
    /// 常駐リンク上のトランスポートを使うかどうかを判定します。
    ///
    /// 責務: 終端がBLEで、そのUUIDが常駐リンクの接続対象と同じで、リンクが `ready` の時だけ常駐リンクを使うと判定します。
    /// - Parameters:
    ///   - endpoint: 接続しようとしている終端。
    ///   - linkTargetIdentifier: 常駐リンクの接続対象のPeripheral UUID。開始されていなければ `nil`。
    ///   - linkState: 常駐リンクの現在の状態。
    /// - Returns: 常駐リンク上のトランスポートを使うなら `true`。
    func usesResidentLink(
        for endpoint: OBDConnectionEndpoint,
        linkTargetIdentifier: UUID?,
        linkState: AdapterLinkState
    ) -> Bool {
        guard endpoint.transport == .bluetoothLowEnergy,
              linkState == .ready,
              let linkTargetIdentifier,
              let endpointIdentifier = UUID(uuidString: endpoint.systemIdentifier) else { return false }
        return endpointIdentifier == linkTargetIdentifier
    }

    /// 常駐リンクだけを使うべきかどうかを踏まえて、使うトランスポートを判定します。
    ///
    /// 責務: 常駐リンクを使える時は常駐リンク、常駐リンクで始めた記録のBLE終端で常駐リンクを使えない時は接続しない、
    /// それ以外(常駐リンクで始めた記録でない・BLE以外の終端)は従来のトランスポートと判定します。
    /// - Parameters:
    ///   - endpoint: 接続しようとしている終端。
    ///   - linkTargetIdentifier: 常駐リンクの接続対象のPeripheral UUID。開始されていなければ `nil`。
    ///   - linkState: 常駐リンクの現在の状態。
    ///   - requiresResidentLink: 常駐リンクで始めた記録の取得で、常駐リンクだけを使うべきなら `true`。
    /// - Returns: 判定結果。
    func selection(
        for endpoint: OBDConnectionEndpoint,
        linkTargetIdentifier: UUID?,
        linkState: AdapterLinkState,
        requiresResidentLink: Bool
    ) -> AdapterLinkTransportSelection {
        if usesResidentLink(for: endpoint, linkTargetIdentifier: linkTargetIdentifier, linkState: linkState) {
            return .residentLink
        }
        guard requiresResidentLink, endpoint.transport == .bluetoothLowEnergy else { return .fallback }
        return .residentLinkUnavailable
    }
}
