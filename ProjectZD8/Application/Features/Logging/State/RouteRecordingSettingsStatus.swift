/// 設定画面の「走行ルートを記録」区画に出す記録の状態です。
nonisolated enum RouteRecordingSettingsStatus: String, Equatable, Sendable, CaseIterable {
    /// 設定がオフです。
    case off
    /// 設定はオンですが、位置情報の許可が未確定です。
    case awaitingPermission
    /// 「常に許可」のため、背面でも記録します。
    case recordsInBackground
    /// 「使用中のみ」のため、前面にいる間だけ記録します。
    case foregroundOnly
    /// 位置情報の利用が拒否されています。
    case denied
    /// 位置情報の利用が制限されています。
    case restricted
    /// このプラットフォームでは記録しません。
    case unsupportedPlatform

    /// 状態の文言のローカライズキーです(`settings.route_recording.status.<snake_case>`)。
    var localizationKey: String {
        "settings.route_recording.status.\(snakeCaseName)"
    }

    /// ローカライズキーの末尾に使う snake_case の名前です。
    private var snakeCaseName: String {
        switch self {
        case .off: "off"
        case .awaitingPermission: "awaiting_permission"
        case .recordsInBackground: "records_in_background"
        case .foregroundOnly: "foreground_only"
        case .denied: "denied"
        case .restricted: "restricted"
        case .unsupportedPlatform: "unsupported_platform"
        }
    }
}
