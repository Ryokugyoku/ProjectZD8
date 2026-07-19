/// 主要PID読取画面からApplicationへ通知する操作です。
enum LiveTelemetryAction: Equatable {
    /// 指定OBD終端から主要PIDの1回読取りを要求します。
    case readRequested(OBDConnectionEndpoint)
    /// 直近の接続終端で再読取を要求します。
    case retryRequested
}
