/// 走行ルートを描けない理由、または一部しか記録できなかった理由です。
nonisolated enum DrivingRouteAbsenceReason: Equatable, Sendable, CaseIterable {
    /// この端末では位置を記録できません(Mac など)。
    case unsupportedPlatform
    /// 設定で位置の記録をオフにしていました。
    case disabledBySetting
    /// 位置情報の利用が制限されていました。
    case authorizationRestricted
    /// 位置情報の利用が許可されていませんでした。
    case authorizationDenied
    /// 位置情報の利用の許可がまだ決まっていませんでした。
    case authorizationNotDetermined
    /// 「常に許可」が無く、バックグラウンドで記録できませんでした。
    case backgroundWithoutAlwaysAuthorization
    /// 位置を取得できませんでした。
    case locationUnavailable
    /// 記録を始めましたが、位置が1件も届きませんでした。
    case noFixesReceived
    /// 届いた位置がすべて精度の検査で除かれました。
    case allFixesInaccurate
    /// 位置の記録がありません。
    case notRecorded
    /// この端末に無く、iCloud にもありません。
    case notInCloud
}
