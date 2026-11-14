/// 接続中のアダプターで次に使うテレメトリ取得方式です。
///
/// 保存済み区間の記録に使う`ConnectionSessionAcquisitionMode`とは別の、取得開始前の方式選択用の型です。
nonisolated enum OBDAcquisitionMode: Equatable, Sendable {
    /// CANバスを受信専用で監視してフレームを取得します。
    case canMonitor
    /// PIDを順に要求して応答を取得します。
    case pidPolling
}
