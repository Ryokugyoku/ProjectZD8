/// 位置情報の利用許可の段階です。
nonisolated enum LocationAuthorizationLevel: String, Equatable, Sendable, CaseIterable {
    /// まだ利用者に確認していません。
    case notDetermined
    /// 利用者が拒否しました。
    case denied
    /// 保護者機能などにより制限されています。
    case restricted
    /// アプリ使用中のみ許可されています。
    case whenInUse
    /// 常に許可されています。
    case always
    /// このプラットフォームでは位置を記録しません。
    case unsupportedPlatform
}
