/// リアルタイムPID取得をApplicationへ通知する操作です。
enum LiveTelemetryAction: Equatable {
    /// 指定OBD終端から車種適用済みの継続取得開始を要求します。
    case startRequested(OBDConnectionEndpoint, VehicleID, vehicleModelCode: String?)
    /// 直近の接続終端で継続取得の再開を要求します。
    case retryRequested
    /// 現在の継続取得を終了します。
    case stopRequested
    /// アプリがバックグラウンドへ移行したことを通知し、保存待ちの取得記録を保存させます。
    case backgroundTransitionOccurred
    /// アプリがフォアグラウンドへ戻ったことを通知し、一時停止中なら復帰を試させます。
    case foregroundTransitionOccurred
    /// アダプターとのリンクが送受信可能(`true`)または切断(`false`)になったことを通知します。
    case adapterLinkAvailabilityChanged(isAvailable: Bool)
}
