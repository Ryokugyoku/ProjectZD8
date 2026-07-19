/// 主要PID読取を完了できなかった理由です。
enum OBDPIDTelemetryError: Error, Equatable {
    /// 実車読取実装が現在のプラットフォームにありません。
    case unavailable
    /// 要求PIDが固定許可リストにありません。
    case unsupportedPID
    /// アダプターまたは車両が要求を拒否しました。
    case commandRejected
    /// 要求と一致する完全な正応答を復元できません。
    case malformedResponse
    /// 要求した全PIDの応答が揃いません。
    case incompleteResponse
}
