import Foundation

/// 整備編集入力の検証で見つかった問題です。
nonisolated enum MaintenanceDraftIssue: Hashable, Sendable {
    /// 表題が空です。
    case titleRequired
    /// 作業項目が1件もありません。
    case workItemRequired
    /// 走行距離が負数または非有限です。
    case odometerInvalid
    /// 重整備の締結グループに名称がありません。
    case fastenerGroupNameRequired(UUID)
    /// 締結の本数またはトルクが負数です。
    case fastenerValueInvalid(UUID)

    /// 画面表示に使用するローカライズキーです。
    var localizationKey: String {
        switch self {
        case .titleRequired: "maintenance.validation.title_required"
        case .workItemRequired: "maintenance.validation.work_item_required"
        case .odometerInvalid: "maintenance.validation.odometer_invalid"
        case .fastenerGroupNameRequired: "maintenance.validation.fastener_group_name_required"
        case .fastenerValueInvalid: "maintenance.validation.fastener_value_invalid"
        }
    }
}
