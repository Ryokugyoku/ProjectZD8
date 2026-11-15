/// 未登録車両のログがあることをホームと車両画面で知らせる警告の表示状態です。
enum UnassignedObservedVINWarning: Equatable, Sendable {
    /// 警告を表示しません。未サインイン、照会前、または対象ログが0件の場合です。
    case hidden
    /// 未登録車両のログがあります。
    case unregisteredVehicles(UnassignedObservedVINSummary)
    /// 照会に失敗し、未登録車両のログの有無を確認できません。
    case loadFailed

    /// 照会結果から警告を生成します。
    ///
    /// 責務: 照会したセッション一覧を、対象が1件以上なら警告、0件なら非表示へ変換します。
    /// - Parameter sessions: 車両未割当かつ観測VINを持つセッションの照会結果。
    init(sessions: [ConnectionSession]) {
        if let summary = UnassignedObservedVINSummary(sessions: sessions) {
            self = .unregisteredVehicles(summary)
        } else {
            self = .hidden
        }
    }

    /// 警告領域を表示するかどうかです。照会失敗も区別して表示します。
    var isVisible: Bool {
        switch self {
        case .hidden:
            false
        case .unregisteredVehicles, .loadFailed:
            true
        }
    }

    /// 警告の見出しを表すローカライズキーです。非表示の場合は `nil` です。
    var titleKey: String? {
        switch self {
        case .hidden:
            nil
        case .unregisteredVehicles:
            "unassigned_vin.warning.title"
        case .loadFailed:
            "unassigned_vin.warning.failure.title"
        }
    }

    /// 警告本文を表すローカライズキーです。
    ///
    /// 未登録車両がある場合の本文は `%1$lld`(車両数)と `%2$lld`(ログ件数)の2引数を取ります。
    /// 車両1台・ログ1件、車両1台・ログ複数、車両複数の3通りで単数/複数を切り替えます。非表示の場合は `nil` です。
    var messageKey: String? {
        switch self {
        case .hidden:
            nil
        case let .unregisteredVehicles(summary):
            if summary.vehicleCount == 1, summary.sessionCount == 1 {
                "unassigned_vin.warning.message.one_vehicle_one_log"
            } else if summary.vehicleCount == 1 {
                "unassigned_vin.warning.message.one_vehicle_many_logs"
            } else {
                "unassigned_vin.warning.message.many_vehicles"
            }
        case .loadFailed:
            "unassigned_vin.warning.failure.message"
        }
    }

    /// 本文の書式へ渡す件数です。未登録車両がある場合だけ `[車両数, ログ件数]`、それ以外は空です。
    var messageArguments: [Int] {
        guard case let .unregisteredVehicles(summary) = self else { return [] }
        return [summary.vehicleCount, summary.sessionCount]
    }

    /// 警告に添えるSF Symbol名です。非表示の場合は `nil` です。
    var systemImageName: String? {
        switch self {
        case .hidden:
            nil
        case .unregisteredVehicles:
            "exclamationmark.triangle.fill"
        case .loadFailed:
            "exclamationmark.circle.fill"
        }
    }

    /// 警告に置く主要操作です。非表示の場合は `nil` です。
    var primaryAction: UnassignedObservedVINWarningPrimaryAction? {
        switch self {
        case .hidden:
            nil
        case let .unregisteredVehicles(summary):
            .registerVehicle(vin: summary.latestVIN)
        case .loadFailed:
            .retryLoading
        }
    }
}
