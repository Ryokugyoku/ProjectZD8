/// 受信監視の試行結果から決めた取得方式の判断です。
nonisolated enum OBDAcquisitionModeDecision: Equatable, Sendable {
    /// フィルターなしでCAN受信監視を行います。
    case canMonitorUnfiltered
    /// 受信IDを絞るフィルターを設定してCAN受信監視を行います。
    case canMonitorFiltered
    /// PIDポーリングで取得します。
    case pidPolling
    /// 試行結果から方式を決められませんでした。
    case undetermined

    /// 判断が示す取得方式です。決められなかった場合はnilです。
    var mode: OBDAcquisitionMode? {
        switch self {
        case .canMonitorUnfiltered, .canMonitorFiltered: .canMonitor
        case .pidPolling: .pidPolling
        case .undetermined: nil
        }
    }

    /// 受信監視を再試行して判断し直す余地があるかどうかです。
    var isRetryable: Bool { self == .undetermined }
}
