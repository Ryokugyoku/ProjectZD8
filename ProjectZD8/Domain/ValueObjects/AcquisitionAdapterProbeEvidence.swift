/// 取得開始前の初期化で判定したアダプターのチップ種別とATMA判定結果の組です。
///
/// 取得モードはPIDポーリング固定のまま、判定結果だけを取得証跡へ残すために使います。
nonisolated struct AcquisitionAdapterProbeEvidence: Equatable, Sendable {
    /// 初期化時に判定したチップ種別です。
    let chipFamily: OBDAdapterChipFamily
    /// `ATMA`による受信監視の試行結果です。`nil` は試行していないことを表します。
    let monitorProbeOutcome: OBDMonitorProbeOutcome?

    /// チップ種別とATMA判定結果を固定して生成します。
    ///
    /// 責務: 1回の初期化で得たアダプター判定結果を不変の証拠値へまとめます。
    /// - Parameters:
    ///   - chipFamily: 初期化時に判定したチップ種別。
    ///   - monitorProbeOutcome: `ATMA` の試行結果。試行していない場合は `nil`。
    init(chipFamily: OBDAdapterChipFamily, monitorProbeOutcome: OBDMonitorProbeOutcome?) {
        self.chipFamily = chipFamily
        self.monitorProbeOutcome = monitorProbeOutcome
    }
}
