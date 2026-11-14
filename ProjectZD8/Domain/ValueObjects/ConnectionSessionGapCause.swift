/// 連続取得区間の間に空白が生じた直接原因です。
nonisolated enum ConnectionSessionGapCause: String, Codable, Equatable, Sendable {
    /// アダプターまたは車両との通信境界が失われました。
    case linkLost
    /// アプリプロセスが終了しました。
    case processTerminated
    /// 応答が一定時間返らなくなりました。
    case responseStall
    /// アダプター側の受信バッファが満杯になりました。
    case adapterBufferFull
    /// アプリ側の保存待ちバッファがあふれました。
    case bufferOverflow
}
