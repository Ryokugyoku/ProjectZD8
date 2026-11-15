import Foundation

/// 車両確認中の進行状況です。確認窓の終了時刻と実行済みの確認回数で再確認の上限を決めます。
nonisolated struct AdapterLinkVehicleConfirmation: Equatable, Sendable {
    /// 初期化時に判定したアダプターのチップ種別とATMA判定結果です。
    let adapterProbeEvidence: AcquisitionAdapterProbeEvidence

    /// 再確認を続けてよい確認窓の終了時刻です。
    let windowEndsAt: Date

    /// この確認窓の中で要求した車両確認の回数です(最初の確認を含む)。
    let attemptCount: Int

    /// 低頻度確認中か休止中かです。
    let phase: AdapterLinkVehicleConfirmationPhase

    /// 車両確認の進行状況を固定して生成します。
    ///
    /// 責務: 確認窓・確認回数・段階を1件の不変値へまとめます。
    /// - Parameters:
    ///   - adapterProbeEvidence: 初期化時のアダプター判定結果。
    ///   - windowEndsAt: 確認窓の終了時刻。
    ///   - attemptCount: 確認窓の中で要求した確認回数。
    ///   - phase: 低頻度確認中か休止中か。
    init(
        adapterProbeEvidence: AcquisitionAdapterProbeEvidence,
        windowEndsAt: Date,
        attemptCount: Int,
        phase: AdapterLinkVehicleConfirmationPhase
    ) {
        self.adapterProbeEvidence = adapterProbeEvidence
        self.windowEndsAt = windowEndsAt
        self.attemptCount = attemptCount
        self.phase = phase
    }
}
