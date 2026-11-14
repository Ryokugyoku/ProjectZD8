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
        /// 取得が途切れ、回復段階を試しているか、猶予内の復帰を待っています。セッションは続いています。
        case paused
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
    /// 現在監視する車両(登録済みならIDと確認済み型式コード、または未登録)です。取得を始めていなければ `nil` です。
    var vehicle: LiveTelemetryVehicleContext?
    /// 直近の失敗を表示するローカライズキーです。
    var failureKey: String?
    /// 回復中または一時停止中の表示状態です。`phase == .paused` の間だけ値を持ちます。
    var pauseStatus: LiveTelemetryPauseStatus?

    /// HOMEで切断操作を提供する接続中段階かどうかです。
    var isConnectionActive: Bool {
        phase == .reading || phase == .loaded || phase == .paused || phase == .stopping
    }

    /// 車両から応答を受信し続けている段階かどうかです。「接続済み」と読める表示はこの値の裏付けがある時だけ出します。
    var isReceiving: Bool {
        phase == .loaded
    }

    /// 通信資源の安全な終了完了を待っているかどうかです。
    var isDisconnecting: Bool {
        phase == .stopping
    }
}
