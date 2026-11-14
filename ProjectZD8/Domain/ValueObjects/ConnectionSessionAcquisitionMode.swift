/// 連続取得区間がデータを取得した方式です。
nonisolated enum ConnectionSessionAcquisitionMode: String, Codable, Equatable, Sendable {
    /// PIDを順に要求して応答を取得します。
    case pidPolling
    /// CANバスを受信専用で監視してフレームを取得します。
    case canMonitor
}
