/// 応答駆動の取得ループを1世代開始するための確定済み入力です。
nonisolated struct LiveTelemetryAcquisitionLoopInput: Equatable, Sendable {
    /// 古いループを無効化するための世代です。
    let generation: UInt
    /// 収集が有効で数値化可能な取得対象の定義です。
    let definitions: [OBDPIDDefinition]
    /// 取得記録へ渡す定義ごとのcapabilityです。記録しない経路では空です。
    let capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]
    /// 物理要求に使うOBD終端です。
    let endpoint: OBDConnectionEndpoint

    /// 1世代の取得対象と終端を固定します。
    ///
    /// 責務: 世代、取得対象定義、capability、終端を1件のループ開始入力へまとめます。
    /// - Parameters:
    ///   - generation: 古いループを無効化するための世代。
    ///   - definitions: 収集が有効で数値化可能な取得対象の定義。
    ///   - capabilities: 取得記録へ渡す定義ごとのcapability。
    ///   - endpoint: 物理要求に使うOBD終端。
    init(
        generation: UInt,
        definitions: [OBDPIDDefinition],
        capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput],
        endpoint: OBDConnectionEndpoint
    ) {
        self.generation = generation
        self.definitions = definitions
        self.capabilities = capabilities
        self.endpoint = endpoint
    }
}
