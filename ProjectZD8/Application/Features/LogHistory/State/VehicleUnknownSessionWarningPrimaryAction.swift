/// 車両不明ログの警告から選べる主要操作です。
nonisolated enum VehicleUnknownSessionWarningPrimaryAction: Equatable, Sendable {
    /// 車両不明ログの一覧を開き、登録済みの車両へ紐付けます。
    case reviewSessions
    /// 照会に失敗したので読み込み直します。
    case retryLoading

    /// ボタンの表示名のローカライズキーです。
    ///
    /// 責務: 操作ごとの表示名キーを返します。
    var titleKey: String {
        switch self {
        case .reviewSessions: "vehicle_unknown.warning.action.review"
        case .retryLoading: "unassigned_vin.warning.action.retry"
        }
    }

    /// ボタンのSF Symbols名です。
    ///
    /// 責務: 操作ごとの記号名を返します。
    var systemImageName: String {
        switch self {
        case .reviewSessions: "link.circle.fill"
        case .retryLoading: "arrow.clockwise"
        }
    }
}
