/// 走行ルートのうち、1本の線につながる区間です。点は1つ以上で、`observedAt` の昇順に並びます。
nonisolated struct DrivingRouteSegment: Equatable, Sendable {
    /// 区間の点(1つ以上、`observedAt` 昇順)です。
    let points: [DrivingRoutePoint]
    /// 区間全体の精度の段階です。
    let precision: DrivingRoutePrecision
}
