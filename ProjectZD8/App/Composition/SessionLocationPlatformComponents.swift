/// 走行ルート記録の組み立てに使う、OSごとの部品一式です。
///
/// iOS は CoreLocation のアダプター、macOS は位置を扱わない代替を入れます。
/// `ApplicationPlatformComposing.makeSessionLocationPlatformComponents()` が生成し、
/// `SessionLocationRecordingAssembly` が共通の配線へ結び付けます。
@MainActor
struct SessionLocationPlatformComponents {
    /// 位置情報の許可の読取と要求の境界です。
    let authorization: any LocationAuthorizationPort
    /// 位置の流れを作る唯一の取得元です。
    let source: any LocationUpdateSourcePort
    /// 「走行ルートを記録」の設定の保存先です。
    let preference: any RouteRecordingPreferencePort
    /// アプリが前面(背面でない)なら `true` を返す処理です。
    let isForeground: @MainActor () -> Bool
}
