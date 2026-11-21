/// 走行ルートを描けない時に出す内容です。
nonisolated struct DrivingRouteUnavailableContent: Equatable, Sendable {
    /// 理由の文言のローカライズキーです。View 側で `LocalizedStringKey` に包みます。
    let messageKey: String
    /// 理由に添える SF Symbols の名前です。
    let systemImage: String
}
