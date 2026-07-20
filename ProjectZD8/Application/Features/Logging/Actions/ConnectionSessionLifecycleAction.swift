/// 接続開始から終了までをLoggingへ通知する操作です。
enum ConnectionSessionLifecycleAction: Equatable {
    /// 現在の認証アカウントへ保存範囲を切り替えます。
    case accountIdentifierChanged(String?)
    /// HOME接続開始を新規セッションとして記録します。
    case startRequested
    /// 接続対象として確定した登録車両を現在セッションへ関連付けます。
    case vehicleResolved(VehicleProfile)
    /// 優先順位を判定できる取得元付き累積距離を現在セッションへ記録します。
    case distanceObserved(ConnectionSessionDistanceObservation)
    /// 現在セッションを指定原因で終了します。
    case endRequested(ConnectionSessionEndReason)
}
