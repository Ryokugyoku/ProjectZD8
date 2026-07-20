/// リアルタイムPID取得と表示に必要な現在状態です。
struct LiveTelemetryState: Equatable {
    /// PID読取処理の現在段階です。
    enum Phase: Equatable {
        /// 読取操作を待っています。
        case idle
        /// DB登録済みPIDの対応状況を探索しています。
        case reading
        /// BRZ Beta周期取得の危険性に対するユーザー判断を待っています。
        case awaitingBRZBetaConsent
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
    /// 読取りまたは再試行に使用するOBD終端です。
    var endpoint: OBDConnectionEndpoint?
    /// 現在監視する車両のアプリ内識別子です。
    var vehicleID: VehicleID?
    /// 現在有効なリアルタイム取得方式です。
    var acquisitionMode: LiveTelemetryAcquisitionMode = .standardPolling
    /// 直近の失敗を表示するローカライズキーです。
    var failureKey: String?

    /// HOMEで切断操作を提供する接続中段階かどうかです。
    var isConnectionActive: Bool {
        phase == .reading || phase == .awaitingBRZBetaConsent || phase == .loaded || phase == .stopping
    }

    /// 通信資源の安全な終了完了を待っているかどうかです。
    var isDisconnecting: Bool {
        phase == .stopping
    }
}
