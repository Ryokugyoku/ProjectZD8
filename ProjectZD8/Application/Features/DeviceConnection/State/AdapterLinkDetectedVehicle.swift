/// 常駐リンク上で検知した車両について、記録開始に引き継ぐ観測値の組です。
nonisolated struct AdapterLinkDetectedVehicle: Equatable, Sendable {
    /// 初期化時に判定したアダプターのチップ種別とATMA判定結果です。
    let adapterProbeEvidence: AcquisitionAdapterProbeEvidence

    /// 車両から読み取ったVINです。読取前・読取不能・読取失敗の場合は `nil` です。
    let vin: String?

    /// アダプター判定結果と読み取ったVINを固定して生成します。
    ///
    /// 責務: 1回の検知で得た観測値を不変の値へまとめます。
    /// - Parameters:
    ///   - adapterProbeEvidence: 初期化時のアダプター判定結果。
    ///   - vin: 読み取ったVIN。読めなかった場合は `nil`。
    init(adapterProbeEvidence: AcquisitionAdapterProbeEvidence, vin: String?) {
        self.adapterProbeEvidence = adapterProbeEvidence
        self.vin = vin
    }
}
