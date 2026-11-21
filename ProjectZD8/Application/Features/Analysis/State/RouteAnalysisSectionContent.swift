/// 解析の「ルート」の表示で、地図の場所に出す内容です。iOS と macOS の解析画面で共有します。
nonisolated enum RouteAnalysisSectionContent: Equatable, Sendable {
    /// 走行ルートを読み込んでいます(表示前・サインイン待ちを含む)。`isLoadingRoute` は読み込みの通信中かです。
    case loading(isLoadingRoute: Bool)
    /// 走行ルートを描けない理由のローカライズキーと、添える SF Symbols の名前です。
    case unavailable(reasonKey: String, systemImage: String)
    /// 読み込みの失敗のローカライズキーと、再試行のボタンを出すかです。
    case failed(messageKey: String, isRetryable: Bool)
    /// 地図に描く内容です。
    case ready(RouteAnalysisMapLayers)
}
