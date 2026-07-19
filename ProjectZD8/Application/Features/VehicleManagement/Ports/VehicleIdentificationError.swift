/// OBD車両識別処理が完了できなかった理由です。
enum VehicleIdentificationError: Error, Equatable {
    /// 実OBD識別実装がCompositionへまだ提供されていません。
    case unavailable
    /// 選択された物理通信方式をこのプラットフォームでは使用できません。
    case transportUnsupported
    /// OBDLink EXのUSBシリアル終端を開けませんでした。
    case connectionFailed
    /// アダプターが期限内に完全な応答を返しませんでした。
    case responseTimedOut
    /// アダプターが要求を理解しないか車両からデータを取得できませんでした。
    case commandRejected
    /// 応答を規格上の車両識別情報として復元できませんでした。
    case malformedResponse
    /// PID専用テーブルを安全に準備できませんでした。
    case pidCatalogUnavailable
    /// VINを取得できなかったため登録照合を継続できません。
    case vinUnavailable
}
