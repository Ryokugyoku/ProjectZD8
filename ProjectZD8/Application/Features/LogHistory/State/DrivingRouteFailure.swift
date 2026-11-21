/// 走行ルートの読み込みの失敗です。
nonisolated struct DrivingRouteFailure: Equatable, Sendable {
    /// 失敗の文言のローカライズキーです。View 側で `LocalizedStringKey` に包みます。
    let messageKey: String
    /// 再試行で直る見込みがある時に `true` です。
    let isRetryable: Bool
}
