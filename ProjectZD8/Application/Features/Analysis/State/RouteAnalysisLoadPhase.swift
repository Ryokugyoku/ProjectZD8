/// 解析の走行ルートの読み込みの段階です。
nonisolated enum RouteAnalysisLoadPhase: Equatable, Sendable {
    /// セッションが表示されていません。
    case idle
    /// サインインを待っています。
    case waitingForAccount
    /// 走行ルートを読み込んでいます。
    case loading
    /// 走行ルートを描けます。
    case ready
    /// 描けない理由のローカライズキーと、添える SF Symbols の名前です。
    case unavailable(reasonKey: String, systemImage: String)
    /// 読み込みの失敗のローカライズキーと、再試行で直る見込みです。
    case failed(messageKey: String, isRetryable: Bool)
}
