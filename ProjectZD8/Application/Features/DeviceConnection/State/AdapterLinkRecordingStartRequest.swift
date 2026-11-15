/// 常駐リンク監視が記録側へ渡す記録開始要求です。登録済み車両の照合は含みません。
nonisolated struct AdapterLinkRecordingStartRequest: Equatable, Sendable {
    /// 記録に使う常駐リンクの接続終端です。
    let endpoint: OBDConnectionEndpoint

    /// 車両から読み取ったVINです。読めなかった場合は `nil` です。
    let vin: String?

    /// 初期化時に判定したアダプターのチップ種別とATMA判定結果です。
    let adapterProbeEvidence: AcquisitionAdapterProbeEvidence

    /// 接続終端と検知時の観測値から記録開始要求を生成します。
    ///
    /// 責務: 記録開始に必要な終端・VIN・アダプター判定結果を1件の不変値へまとめます。
    /// - Parameters:
    ///   - endpoint: 記録に使う接続終端。
    ///   - vin: 読み取ったVIN。
    ///   - adapterProbeEvidence: アダプター判定結果。
    init(endpoint: OBDConnectionEndpoint, vin: String?, adapterProbeEvidence: AcquisitionAdapterProbeEvidence) {
        self.endpoint = endpoint
        self.vin = vin
        self.adapterProbeEvidence = adapterProbeEvidence
    }

    /// 常駐リンクの接続対象設定と検知した車両から記録開始要求を生成します。
    ///
    /// 責務: 接続対象の既定アダプター設定をBLE接続終端へ変換し、検知時の観測値と組み合わせます。
    /// - Parameters:
    ///   - preference: 常駐リンクの接続対象として開始した既定アダプター設定。
    ///   - vehicle: 検知した車両の観測値。
    init(preference: DefaultAdapterPreference, vehicle: AdapterLinkDetectedVehicle) {
        self.init(
            endpoint: OBDConnectionEndpoint(
                transport: preference.connectionTransport,
                systemIdentifier: preference.systemIdentifier,
                displayName: preference.displayName
            ),
            vin: vehicle.vin,
            adapterProbeEvidence: vehicle.adapterProbeEvidence
        )
    }
}
