/// リアルタイムPID取得をApplicationへ通知する操作です。
enum LiveTelemetryAction: Equatable {
    /// 指定OBD終端から継続取得の開始を要求します。
    case startRequested(OBDConnectionEndpoint, VehicleID)
    /// 直近の接続終端で継続取得の再開を要求します。
    case retryRequested
    /// 現在の継続取得を終了します。
    case stopRequested
}
