/// リアルタイムPID取得をApplicationへ通知する操作です。
enum LiveTelemetryAction: Equatable {
    /// 指定要求の終端から継続取得開始を要求します。車両未登録の要求も受け付けます。
    case startRequested(LiveTelemetryStartRequest)
    /// 直近の開始要求と同じ条件で継続取得の再開を要求します。
    case retryRequested
    /// 現在の継続取得を終了します。
    case stopRequested
}
