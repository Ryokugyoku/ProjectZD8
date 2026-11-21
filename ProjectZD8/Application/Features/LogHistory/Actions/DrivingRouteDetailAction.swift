/// セッション詳細の走行ルート(地図)への操作です。
enum DrivingRouteDetailAction: Equatable {
    /// サインイン中のアカウントが変わりました(サインアウトでは `nil`)。
    case accountIdentifierChanged(String?)
    /// セッションの詳細が表示されました。
    case sessionShown(ConnectionSession)
    /// セッションの詳細が閉じられました。取得中の iCloud 通信を取り消します。
    case sessionHidden(ConnectionSessionID)
    /// 失敗した読み込みの再試行が求められました。
    case retryRequested
}
