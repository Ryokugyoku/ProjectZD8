/// 接続セッションが終了した直接原因です。
enum ConnectionSessionEndReason: String, Codable, Equatable, Sendable {
    /// HOMEの切断操作によって終了しました。
    case userDisconnected
    /// 車両から有効な応答が返らなくなりました。
    case vehicleNoResponse
    /// アダプターまたは車両との通信境界が失われました。
    case connectionLost
    /// PID定義または読取開始に失敗しました。
    case acquisitionFailed
    /// 新しい接続要求によって以前のセッションが置き換えられました。
    case superseded
    /// アカウントのサインアウトによって終了しました。
    case accountSignedOut
    /// アプリ終了などにより終了処理を完了できませんでした。
    case unexpectedTermination
}
