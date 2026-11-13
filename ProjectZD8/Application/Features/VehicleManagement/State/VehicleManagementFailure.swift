/// 車両管理で起きる失敗を、画面が文言へ変換できる型で表します。
nonisolated enum VehicleManagementFailure: Error, Equatable, Sendable {
    /// 車両一覧またはアクティビティ集計を読み込めなかった。
    case loadFailed
    /// 対象の車両が見つからなかった。
    case vehicleNotFound
    /// 入力内容が検証に通らなかった。
    case invalidInput
    /// 車両を保存できなかった。
    case saveFailed
    /// 写真を保存または削除できなかった。
    case photoFailed
    /// 写真を読み込めなかった。
    case photoLoadFailed
    /// 車両を削除できなかった。
    case deleteFailed
    /// 記録中のセッションがあるため削除を拒否した。
    case deleteRefusedWhileRecording
    /// PID収集設定を読み込めなかった、または保存できなかった。
    case pidSettingsFailed
    /// 車両が応答を確認していないPIDの収集は切り替えられない。
    case pidNotSupported

    /// 画面表示に使用するローカライズキーです。
    var localizationKey: String {
        switch self {
        case .loadFailed: "garage.error.load"
        case .vehicleNotFound: "garage.error.vehicle_not_found"
        case .invalidInput: "garage.error.invalid_input"
        case .saveFailed: "garage.error.save"
        case .photoFailed: "garage.error.photo"
        case .photoLoadFailed: "garage.error.photo_load"
        case .deleteFailed: "garage.error.delete"
        case .deleteRefusedWhileRecording: "garage.error.delete_active_session"
        case .pidSettingsFailed: "garage.error.pid_settings"
        case .pidNotSupported: "garage.error.pid_not_supported"
        }
    }
}
