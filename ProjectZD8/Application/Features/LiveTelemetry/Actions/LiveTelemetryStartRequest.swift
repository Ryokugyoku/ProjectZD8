/// リアルタイムPID継続取得の開始と再開に使用する確定済み要求です。
nonisolated struct LiveTelemetryStartRequest: Equatable, Sendable {
    /// PID要求を送るOBDアダプターの物理終端です。
    let endpoint: OBDConnectionEndpoint
    /// 対応PID設定を参照する登録車両IDです。`nil` は車両未登録のまま記録することを表します。
    let vehicleID: VehicleID?
    /// 車種専用PIDの適用に使用する確認済み型式コードです。
    let vehicleModelCode: String?
    /// 初期化時に判定したアダプターのチップ種別とATMA判定結果です。`nil` は判定結果がないことを表します。
    let adapterProbeEvidence: AcquisitionAdapterProbeEvidence?

    /// 取得開始に必要な終端、車両、型式、アダプター判定結果を固定します。
    ///
    /// 責務: 1回の取得開始要求を再試行でも同じ条件で再開できる値へまとめます。
    /// - Parameters:
    ///   - endpoint: PID要求を送るOBDアダプターの物理終端。
    ///   - vehicleID: 対応PID設定を参照する登録車両ID。車両未登録の場合は `nil`。
    ///   - vehicleModelCode: 車種専用PIDの適用に使用する確認済み型式コード。
    ///   - adapterProbeEvidence: 初期化時に判定したアダプター判定結果。判定していない場合は `nil`。
    init(
        endpoint: OBDConnectionEndpoint,
        vehicleID: VehicleID?,
        vehicleModelCode: String?,
        adapterProbeEvidence: AcquisitionAdapterProbeEvidence? = nil
    ) {
        self.endpoint = endpoint
        self.vehicleID = vehicleID
        self.vehicleModelCode = vehicleModelCode
        self.adapterProbeEvidence = adapterProbeEvidence
    }
}
