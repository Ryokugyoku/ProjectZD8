/// 軌跡の取得結果から決めた、走行ルートの表示の状態です。
nonisolated struct DrivingRouteStatus: Equatable, Sendable {
    /// 描ける点が1つ以上ある時だけの走行ルートです。
    let route: DrivingRoute?
    /// `route` が `nil` の時に出す内容です。
    let absence: DrivingRouteUnavailableContent?
    /// 注記のローカライズキー(表示順: 部分 → 概略 → 除外 → 未確認の復元)です。
    let noticeKeys: [String]
}
