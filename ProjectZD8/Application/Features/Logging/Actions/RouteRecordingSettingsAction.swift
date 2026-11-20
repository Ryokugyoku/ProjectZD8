/// 軌跡記録設定の画面から送られる操作です。
enum RouteRecordingSettingsAction: Equatable {
    /// 記録のオン・オフが切り替えられました。
    case toggled(isEnabled: Bool)
    /// 位置情報の許可状態が変わりました。
    case permissionChanged(LocationPermission)
}
