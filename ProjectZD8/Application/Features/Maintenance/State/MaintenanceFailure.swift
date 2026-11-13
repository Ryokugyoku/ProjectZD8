/// 整備機能で起きる失敗を、画面が文言へ変換できる型で表します。
nonisolated enum MaintenanceFailure: Error, Equatable, Sendable {
    /// 車両または整備記録を読み込めなかった。
    case loadFailed
    /// 整備を記録する車両が選ばれていない。
    case vehicleRequired
    /// 対象の整備記録が見つからなかった。
    case recordNotFound
    /// 入力内容が検証に通らなかった。
    case invalidInput
    /// 整備記録を保存できなかった。
    case saveFailed
    /// 写真を保存または削除できなかった。
    case photoFailed
    /// 写真を読み込めなかった。
    case photoLoadFailed
    /// 整備記録を削除できなかった。
    case deleteFailed

    /// 画面表示に使用するローカライズキーです。
    var localizationKey: String {
        switch self {
        case .loadFailed: "maintenance.error.load"
        case .vehicleRequired: "maintenance.error.vehicle_required"
        case .recordNotFound: "maintenance.error.not_found"
        case .invalidInput: "maintenance.error.required"
        case .saveFailed: "maintenance.error.save"
        case .photoFailed: "maintenance.error.photo"
        case .photoLoadFailed: "maintenance.error.photo_load"
        case .deleteFailed: "maintenance.error.delete"
        }
    }
}
