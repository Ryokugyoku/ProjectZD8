/// 位置記録の状態の種類です。`rawValue` は永続化の CHECK 制約に固定されるため変更しません。
nonisolated enum ConnectionSessionLocationEventKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// 正確な位置を記録しています。
    case recording
    /// 概略の位置だけを記録しています。
    case recordingWithReducedAccuracy
    /// 利用者の設定で記録をオフにしています。
    case disabledBySetting
    /// 許可が未確定のため記録していません。
    case authorizationNotDetermined
    /// 許可が拒否されているため記録していません。
    case authorizationDenied
    /// 制限されているため記録していません。
    case authorizationRestricted
    /// 使用中のみの許可で背面にいるため記録していません。
    case backgroundWithoutAlwaysAuthorization
    /// 位置を取得できない状態です。
    case locationUnavailable
    /// このプラットフォームでは記録しません。
    case unsupportedPlatform
}
