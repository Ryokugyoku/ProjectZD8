/// 主要PID読取を完了できなかった理由です。
enum OBDPIDTelemetryError: Error, Equatable {
    /// PID定義DBが利用不能または空です。
    case definitionCatalogUnavailable
    /// 実車読取実装が現在のプラットフォームにありません。
    case unavailable
    /// アダプター管理の周期送信が利用できません。
    case periodicMessagingUnavailable
    /// 要求PIDが固定許可リストにありません。
    case unsupportedPID
    /// アダプターまたは車両が要求を拒否しました。
    case commandRejected
    /// 要求と一致する完全な正応答を復元できません。
    case malformedResponse
    /// 要求した全PIDの応答が揃いません。
    case incompleteResponse
    /// 要求したPID群に対するECU応答が1件もありません。
    case noVehicleResponse
    /// アダプターまたは車両との通信境界が失われました。
    case connectionLost
}
