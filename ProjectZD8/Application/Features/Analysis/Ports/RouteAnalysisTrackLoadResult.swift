/// 解析のために走行ルートを読み込んだ結果です。失敗も値で表します。
nonisolated enum RouteAnalysisTrackLoadResult: Equatable, Sendable {
    /// 区切った走行ルートと、添える注記のローカライズキーです。
    case available(DrivingRoute, noticeKeys: [String])
    /// 描けない理由のローカライズキーと、添える SF Symbols の名前です。
    case unavailable(reasonKey: String, systemImage: String)
    /// 読み込みの失敗のローカライズキーと、再試行で直る見込みです。
    case failed(messageKey: String, isRetryable: Bool)
}
