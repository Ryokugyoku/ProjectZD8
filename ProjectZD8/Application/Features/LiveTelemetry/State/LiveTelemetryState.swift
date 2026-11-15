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
        /// 取得停止と通信資源の解放完了を待っています。
        case stopping
        /// PID読取または数値化に失敗しました。
        case failed
    }

    /// 現在の処理段階です。
    var phase: Phase = .idle
    /// PIDごとの最新数値観測です。
    var samples: [OBDPIDSample] = []
    /// 初回探索で応答が確認できたPID数です。
    var supportedPIDCount = 0
    /// 読取りまたは再試行に使用する直近の開始要求です。
    var startRequest: LiveTelemetryStartRequest?
    /// 直近の失敗を表示するローカライズキーです。
    var failureKey: String?

    /// 読取りまたは再試行に使用するOBD終端です。
    var endpoint: OBDConnectionEndpoint? {
        startRequest?.endpoint
    }

    /// 現在監視する車両のアプリ内識別子です。車両未登録で記録中の場合は `nil` です。
    var vehicleID: VehicleID? {
        startRequest?.vehicleID
    }

    /// 車種専用PIDの適用に使用する確認済み型式コードです。
    var vehicleModelCode: String? {
        startRequest?.vehicleModelCode
    }

    /// HOMEで切断操作を提供する接続中段階かどうかです。
    var isConnectionActive: Bool {
        phase == .reading || phase == .loaded || phase == .stopping
    }

    /// 通信資源の安全な終了完了を待っているかどうかです。
    var isDisconnecting: Bool {
        phase == .stopping
    }
}
