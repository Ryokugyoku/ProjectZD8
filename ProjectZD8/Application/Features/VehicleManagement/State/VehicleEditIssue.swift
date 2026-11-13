/// 車両編集入力の検証で見つかった問題です。
nonisolated enum VehicleEditIssue: Equatable, Sendable {
    /// 名称が空です。
    case nameRequired
    /// 燃料タンク容量が0以下です。
    case tankCapacityInvalid
    /// 年式が範囲外です。
    case modelYearInvalid

    /// 画面表示に使用するローカライズキーです。
    var localizationKey: String {
        switch self {
        case .nameRequired: "garage.validation.name_required"
        case .tankCapacityInvalid: "garage.validation.tank_invalid"
        case .modelYearInvalid: "garage.validation.model_year_invalid"
        }
    }
}
