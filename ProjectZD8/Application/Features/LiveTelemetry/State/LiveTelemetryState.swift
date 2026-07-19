/// リアルタイムPID取得と表示に必要な現在状態です。
struct LiveTelemetryState: Equatable {
    /// PID読取処理の現在段階です。
    enum Phase: Equatable {
        /// 読取操作を待っています。
        case idle
        /// DB登録済みPIDの対応状況を探索しています。
        case reading
        /// 応答済みPIDを継続取得しています。
        case loaded
        /// PID読取または数値化に失敗しました。
        case failed
    }

    /// 現在の処理段階です。
    var phase: Phase = .idle
    /// PIDごとの最新数値観測です。
    var samples: [OBDPIDSample] = []
    /// 初回探索で応答が確認できたPID数です。
    var supportedPIDCount = 0
    /// 読取りまたは再試行に使用するOBD終端です。
    var endpoint: OBDConnectionEndpoint?
    /// 直近の失敗を表示するローカライズキーです。
    var failureKey: String?
}
