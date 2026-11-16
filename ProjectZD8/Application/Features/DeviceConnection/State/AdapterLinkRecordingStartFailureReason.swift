/// 通知の[記録開始]から記録を始められなかった理由です。「記録を開始できませんでした」通知の本文を決めます。
nonisolated enum AdapterLinkRecordingStartFailureReason: Equatable, Sendable, CaseIterable {
    /// 有効期限内に車両を検知できなかった(または監視が動いていなかった)。
    case vehicleNotDetected
    /// サインインしていない。
    case signInRequired
    /// 既定のBLEアダプターが設定されていない。
    case adapterNotConfigured

    /// 通知本文のローカライズキーです。
    ///
    /// 責務: 理由ごとの本文キーを返します。
    var bodyKey: String {
        switch self {
        case .vehicleNotDetected: "vehicle-detection-recording-start-failed-body-not-detected"
        case .signInRequired: "vehicle-detection-recording-start-failed-body-sign-in"
        case .adapterNotConfigured: "vehicle-detection-recording-start-failed-body-no-adapter"
        }
    }
}
