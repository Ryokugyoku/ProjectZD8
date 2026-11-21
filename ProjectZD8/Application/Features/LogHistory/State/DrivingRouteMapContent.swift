/// 走行ルートを描ける時に地図カードへ出す内容です。
nonisolated struct DrivingRouteMapContent: Equatable, Sendable {
    /// 地図に描く形です。
    let geometry: DrivingRouteMapGeometry
    /// 要約の文字列です。
    let summary: DrivingRouteSummaryText
    /// 注記のローカライズキー(表示順)です。
    let noticeKeys: [String]
}
