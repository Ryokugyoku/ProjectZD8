/// 走行ルートを、地図に描く形(間引いた折れ線・端の印・表示範囲)へ変換します。
///
/// MapKit の型は使わず、座標は `GeoCoordinate`、範囲は `GeoBoundingBox` で表します。
/// - 2点以上の区間ごとに折れ線を1本作ります。1点だけの区間は線にしませんが、範囲と印には含めます。
/// - 出発の印は最初の点に置きます。到着の印は、セッションが終了済みで、最後の点が最初の点と異なる時だけ置きます。
/// - 折れ線の点の合計は `pointBudget` 以下に間引きます。
nonisolated struct DrivingRouteMapContentBuilder: Sendable {
    /// 出発の印の番号です。
    private static let startMarkerID = 0
    /// 到着の印の番号です。
    private static let endMarkerID = 1

    /// 折れ線の間引きです。
    private let simplifier: GeoPolylineSimplifier
    /// 折れ線の点の合計の上限です。
    private let pointBudget: Int

    /// 間引きと点数の上限を固定して生成します。
    ///
    /// 責務: 形の変換に使う間引きと上限を保持します。
    /// - Parameters:
    ///   - simplifier: 折れ線の間引き。
    ///   - pointBudget: 折れ線の点の合計の上限(既定は 4,000)。
    init(simplifier: GeoPolylineSimplifier = .init(), pointBudget: Int = 4_000) {
        self.simplifier = simplifier
        self.pointBudget = pointBudget
    }

    /// 走行ルートを地図に描く形へ変換します。
    ///
    /// 責務: 折れ線・印・範囲をそろえ、描ける点が無ければ `nil` を返します。
    /// - Parameters:
    ///   - route: 区切った走行ルート。
    ///   - sessionHasEnded: セッションが終了済みなら `true`。
    /// - Returns: 地図に描く形。描ける点が無ければ `nil`。
    func geometry(for route: DrivingRoute, sessionHasEnded: Bool) -> DrivingRouteMapGeometry? {
        guard let first = route.firstPoint,
              let last = route.lastPoint,
              let bounds = GeoBoundingBox(enclosing: route.points.map(\.coordinate))
        else {
            return nil
        }
        return DrivingRouteMapGeometry(
            polylines: polylines(of: route),
            markers: Self.markers(first: first, last: last, sessionHasEnded: sessionHasEnded),
            bounds: bounds
        )
    }

    /// 2点以上の区間を、間引いた折れ線にします。
    ///
    /// 責務: 線になる区間だけを選び、点の合計を上限以下へ間引き、区間の順に番号を振ります。
    /// - Parameter route: 区切った走行ルート。
    /// - Returns: 区間の順の折れ線。
    private func polylines(of route: DrivingRoute) -> [DrivingRouteMapPolyline] {
        let lineSegments = route.segments.filter { $0.points.count >= 2 }
        let simplified = simplifier.simplify(
            lineSegments.map { $0.points.map(\.coordinate) },
            pointBudget: pointBudget
        )
        return zip(lineSegments, simplified).enumerated().map { index, pair in
            DrivingRouteMapPolyline(id: index, coordinates: pair.1, isApproximate: pair.0.precision == .approximate)
        }
    }

    /// 端の印を並べます。
    ///
    /// 責務: 出発の印を必ず置き、終了済みで最後の点が最初の点と異なる時だけ到着の印を足します。
    /// - Parameters:
    ///   - first: ルートの最初の点。
    ///   - last: ルートの最後の点。
    ///   - sessionHasEnded: セッションが終了済みなら `true`。
    /// - Returns: 出発(と到着)の印。
    private static func markers(
        first: DrivingRoutePoint,
        last: DrivingRoutePoint,
        sessionHasEnded: Bool
    ) -> [DrivingRouteMapMarker] {
        var markers = [DrivingRouteMapMarker(id: startMarkerID, coordinate: first.coordinate, endpoint: .start)]
        if sessionHasEnded, last != first {
            markers.append(DrivingRouteMapMarker(id: endMarkerID, coordinate: last.coordinate, endpoint: .end))
        }
        return markers
    }
}
