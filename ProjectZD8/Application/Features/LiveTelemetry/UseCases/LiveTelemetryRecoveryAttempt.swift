/// 回復の試行1回の結果です。
nonisolated enum LiveTelemetryRecoveryAttempt: Equatable, Sendable {
    /// 回復操作が成功し、確認要求にも正応答がありました。
    case resumed
    /// 回復操作が失敗しました(アダプター自体が応答しません)。
    case adapterFailed
    /// 回復操作は成功しましたが、確認要求が正応答になりませんでした(車両が応答しません)。
    case vehicleSilent

    /// 車両応答なし(エンジン停止)の根拠になるかどうかを返します。
    ///
    /// 責務: アダプターが応答するのに確認要求が無応答で、途切れの原因が応答途絶の場合だけ根拠とします。
    /// リンク断はアダプターへ届かない状態のため根拠にしません。
    /// - Parameter cause: 途切れの原因。
    /// - Returns: 車両応答なしの根拠になる場合は `true`。
    func isVehicleOffEvidence(for cause: LiveTelemetryInterruptionCause) -> Bool {
        self == .vehicleSilent && cause == .responseStall
    }
}
