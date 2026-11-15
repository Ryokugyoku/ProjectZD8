/// 1回の継続取得で照会するPID定義と、取得証跡へ固定する対応状況の組です。
nonisolated struct LiveTelemetryAcquisitionTargets: Sendable {
    /// 取得対象として確定した数値化可能PID定義です。
    let definitions: [OBDPIDDefinition]
    /// PID定義ごとの確認済み対応状況と収集選択です。対応状況を確認していない取得経路では空です。
    let capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]

    /// 取得対象定義と対応状況を固定します。
    ///
    /// 責務: 取得対象PIDの決定結果を取得loopと取得証跡の入力へまとめます。
    /// - Parameters:
    ///   - definitions: 取得対象として確定した数値化可能PID定義。
    ///   - capabilities: PID定義ごとの確認済み対応状況と収集選択。
    init(
        definitions: [OBDPIDDefinition],
        capabilities: [ConnectionSessionAcquisitionPIDCapabilityInput]
    ) {
        self.definitions = definitions
        self.capabilities = capabilities
    }
}
