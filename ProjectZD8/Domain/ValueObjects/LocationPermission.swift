/// 位置情報の利用許可の状態です。
nonisolated struct LocationPermission: Equatable, Sendable {
    /// 許可の段階。
    let level: LocationAuthorizationLevel
    /// 正確な位置が許可されている場合は `true`。概略の位置のみなら `false`。
    let isPreciseAccuracy: Bool

    /// 位置を扱わないプラットフォーム用の許可状態です。
    static let unsupportedPlatform = LocationPermission(level: .unsupportedPlatform, isPreciseAccuracy: false)
}
