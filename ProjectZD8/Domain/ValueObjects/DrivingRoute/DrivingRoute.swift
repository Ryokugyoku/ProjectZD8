/// 1セッションの軌跡を、途切れと精度で区間に分けた走行ルートです。
nonisolated struct DrivingRoute: Equatable, Sendable {
    /// 時刻順に並んだ区間です。
    let segments: [DrivingRouteSegment]
    /// 軌跡のサンプル数(除いた点を含む)です。
    let totalFixCount: Int
    /// 精度・座標の不正で除いたサンプル数です。
    let excludedFixCount: Int

    /// 区間が1つも無い時に `true` です。
    var isEmpty: Bool {
        segments.isEmpty
    }

    /// 全区間の点を区間の順に連結した列です。
    var points: [DrivingRoutePoint] {
        segments.flatMap(\.points)
    }

    /// 最初の区間の最初の点です。点が無ければ `nil` です。
    var firstPoint: DrivingRoutePoint? {
        segments.lazy.compactMap(\.points.first).first
    }

    /// 最後の区間の最後の点です。点が無ければ `nil` です。
    var lastPoint: DrivingRoutePoint? {
        segments.reversed().lazy.compactMap(\.points.last).first
    }
}
