/// 未登録車両の警告に置く主要操作です。
enum UnassignedObservedVINWarningPrimaryAction: Equatable, Sendable {
    /// 観測VINを引き継いで車両登録画面へ進みます。
    case registerVehicle(vin: String)
    /// 未登録車両のログを照会し直します。
    case retryLoading

    /// ボタン名を表すローカライズキーです。
    var titleKey: String {
        switch self {
        case .registerVehicle:
            "unassigned_vin.warning.action.register"
        case .retryLoading:
            "unassigned_vin.warning.action.retry"
        }
    }

    /// ボタンに添えるSF Symbol名です。
    var systemImageName: String {
        switch self {
        case .registerVehicle:
            "plus.circle.fill"
        case .retryLoading:
            "arrow.clockwise"
        }
    }
}
