/// 接続セッション内で連続取得区間が終わった直接原因です。
nonisolated enum ConnectionSessionSegmentEndReason: String, Codable, Equatable, Sendable {
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
    /// 取得モードの切替によって区間を閉じました。
    case modeSwitched
    /// 接続セッションの終了によって区間を閉じました。
    case sessionEnded
}
