/// 主要PIDの1回読取りと表示に必要な現在状態です。
struct LiveTelemetryState: Equatable {
    /// PID読取処理の現在段階です。
    enum Phase: Equatable {
        /// 読取操作を待っています。
        case idle
        /// 実車から主要PIDを読み取っています。
        case reading
        /// 主要PIDの数値化を完了しました。
        case loaded
        /// PID読取または数値化に失敗しました。
        case failed
    }

    /// 現在の処理段階です。
    var phase: Phase = .idle
    /// 数値化できた主要PID観測です。
    var samples: [OBDPIDSample] = []
    /// 読取りまたは再試行に使用するOBD終端です。
    var endpoint: OBDConnectionEndpoint?
    /// 直近の失敗を表示するローカライズキーです。
    var failureKey: String?
}
