/// リアルタイムPID取得をApplicationへ通知する操作です。
enum LiveTelemetryAction: Equatable {
    /// 指定OBD終端から車種適用済みの継続取得開始を要求します。
    case startRequested(OBDConnectionEndpoint, VehicleID, vehicleModelCode: String?)
    /// 直近の接続終端で継続取得の再開を要求します。
    case retryRequested
    /// 現在の継続取得を終了します。
    case stopRequested
}
