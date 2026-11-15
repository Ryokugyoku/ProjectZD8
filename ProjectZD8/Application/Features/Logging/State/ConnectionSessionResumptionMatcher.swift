import Foundation

/// プロセス復帰後に続行可能なセッションを、次の接続で続けてよいかを判定します。
///
/// 同じ登録済み車両、またはどちらも車両なし(未登録)で、実時間で猶予内なら続けます。
/// 接続セッションはアダプター終端を保存していないため、プロセスをまたいだ終端の一致は判定に使いません。
nonisolated struct ConnectionSessionResumptionMatcher: Sendable {
    /// 実時間の猶予を判定する方針です。
    private let relaunchPolicy = AcquisitionRelaunchPolicy()

    /// 状態を持たない判定を生成します。
    ///
    /// 責務: 続行判定を構築します。
    init() {}

    /// 続行可能なセッションを次の接続で続けるかを返します。
    ///
    /// 責務: 車両の一致(どちらも `nil` を一致とみなす)と実時間の猶予を両方満たすかを判定します。
    /// - Parameters:
    ///   - resumableVehicleID: 続行可能なセッションに結び付いた車両ID。未登録なら `nil`。
    ///   - connectingVehicleID: 次の接続で確定した車両ID。未登録なら `nil`。
    ///   - lastCommittedAt: 続行可能なセッションで最後にcommitしたRawの観測時刻。
    ///   - now: 判定する時点の実時間。
    /// - Returns: 続ける場合は `true`。
    func canResume(
        resumableVehicleID: VehicleID?,
        connectingVehicleID: VehicleID?,
        lastCommittedAt: Date,
        now: Date
    ) -> Bool {
        resumableVehicleID == connectingVehicleID
            && relaunchPolicy.decision(lastCommittedAt: lastCommittedAt, now: now) == .continueWaiting
    }
}
