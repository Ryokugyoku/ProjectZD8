/// 車両不明ログの警告と紐付け画面への操作です。
enum VehicleUnknownSessionAction: Equatable, Sendable {
    /// サインイン中のアカウントが変わりました(サインアウトでは `nil`)。
    case accountIdentifierChanged(String?)
    /// 警告を読み込み直します。
    case refreshRequested
    /// 警告の主要操作が選ばれました。
    case warningActionSelected(VehicleUnknownSessionWarningPrimaryAction)
    /// 紐付け画面を閉じました。
    case assignmentDismissed
    /// ログの選択を切り替えました。
    case sessionSelectionToggled(ConnectionSessionID)
    /// 紐付ける車両を選びました。
    case vehicleSelected(VehicleID)
    /// 選んだログを、候補の車両のうち選んだ車両へ紐付けます。
    case assignRequested(vehicles: [VehicleProfile])
}
