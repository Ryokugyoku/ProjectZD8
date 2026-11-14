import Foundation

/// 接続開始から終了までをLoggingへ通知する操作です。
enum ConnectionSessionLifecycleAction: Equatable {
    /// 現在の認証アカウントへ保存範囲を切り替えます。
    case accountIdentifierChanged(String?)
    /// セッション終了時のiCloud自動アップロード設定を反映します。
    case automaticUploadChanged(Bool)
    /// HOME接続開始を新規セッションとして記録します。
    case startRequested
    /// 接続対象として確定した登録車両を現在セッションへ関連付けます。
    case vehicleResolved(VehicleProfile)
    /// 接続対象が未登録車両と確定し、車両なしで現在セッションを始めます。
    case vehicleUnregistered
    /// 車両なしで始めたセッションの途中で登録された車両を、取得を切り替えずに現在セッションへ関連付けます。
    case unregisteredVehicleRegistered(VehicleProfile)
    /// 優先順位を判定できる取得元付き累積距離を現在セッションへ記録します。
    case distanceObserved(ConnectionSessionDistanceObservation)
    /// 現在セッションを指定原因で終了します。終了時刻を省略すると処理した時刻を使います。
    case endRequested(ConnectionSessionEndReason, endedAt: Date? = nil)
}
