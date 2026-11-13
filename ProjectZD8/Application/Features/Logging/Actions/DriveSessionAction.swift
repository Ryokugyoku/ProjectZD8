/// 記録の流れへの操作です。
nonisolated enum DriveSessionAction: Equatable, Sendable {
    /// 指定アダプターへ接続し、記録を始めます。`idle` 以外では無視します。
    case connectRequested(AdapterDescriptor)
    /// 未登録の車両を、入力された名前で登録して記録を続けます。
    case registrationSubmitted(name: String)
    /// 車両登録を取りやめ、接続を閉じます。
    case registrationCancelled
    /// 記録または接続の流れを止めます。
    case stopRequested
    /// 表示中の失敗を閉じます。
    case failureDismissed
    /// アプリ起動時に、前回閉じられなかったセッションを終了します。
    case appLaunched
}
