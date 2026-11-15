/// 未登録車両の警告へ通知する操作です。
enum UnassignedObservedVINWarningAction: Equatable, Sendable {
    /// サインイン中のアカウントが変わったことを通知します。未サインインは `nil` です。
    case accountIdentifierChanged(String?)
    /// 現在のアカウントで照会し直すことを通知します。
    case refreshRequested
}
