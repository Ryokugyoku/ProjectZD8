/// リアルタイム値を取得する接続方式です。
enum LiveTelemetryAcquisitionMode: Equatable {
    /// アプリが対応PIDを優先度付きで照会する標準方式です。
    case standardPolling
    /// OBDLinkへ回転数と車速の周期送信を委譲するBRZ限定試験方式です。
    case brzBetaPeriodic
}
