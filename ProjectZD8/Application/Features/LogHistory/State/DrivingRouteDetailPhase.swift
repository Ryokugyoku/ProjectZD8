/// セッション詳細の走行ルートの読み込みの段階です。
nonisolated enum DrivingRouteDetailPhase: Equatable, Sendable {
    /// セッションが表示されていません。
    case idle
    /// サインインを待っています。
    case waitingForAccount
    /// 軌跡を読み込んでいます。
    case loading
    /// 地図に描ける内容があります。
    case loaded(DrivingRouteMapContent)
    /// 描けない理由と、添える注記のローカライズキーです。
    case unavailable(DrivingRouteUnavailableContent, noticeKeys: [String])
    /// 読み込みに失敗しました。
    case failed(DrivingRouteFailure)
}
