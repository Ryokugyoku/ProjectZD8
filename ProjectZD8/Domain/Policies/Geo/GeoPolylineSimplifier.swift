import Foundation

/// 複数の折れ線を、形を保ちながら合計の点数の上限まで減らします(Douglas–Peucker)。
///
/// - 合計の点数が上限以下なら、入力をそのまま返します。
/// - 許容誤差を初期値から倍々にし(最後は上限の値ちょうど)、合計が上限以下になった最初の許容誤差の結果を返します。
///   許容誤差より遠い(ちょうどは除く)点を残します。
/// - 上限の許容誤差でも超える時は、その結果の各折れ線を、端点を残して等間隔に間引きます。
///   上限が「端点の数」(2点以上の折れ線は2、1点は1)の合計に届かない時は端点だけを返します(上限を超えることがあります)。
/// - 2点以上の折れ線は始点と終点を必ず残し、点の順序を保ちます。1点・0点の折れ線はそのままです。
/// - 再帰を使わず、明示的なスタックで反復します。
nonisolated struct GeoPolylineSimplifier: Sendable {
    /// 許容誤差を倍々にする回数の上限です(初期値が極端に小さい時でも止まるように)。
    private static let maximumToleranceSteps = 64

    /// 最初に試す許容誤差(m)。
    private let initialToleranceMeters: Double
    /// 試す許容誤差の上限(m)。
    private let maximumToleranceMeters: Double

    /// 許容誤差の範囲を決めて作ります。
    ///
    /// 責務: 倍々に試す許容誤差の初期値と上限を保持します。
    /// - Parameters:
    ///   - initialToleranceMeters: 最初の許容誤差(m)。
    ///   - maximumToleranceMeters: 許容誤差の上限(m)。
    init(initialToleranceMeters: Double = 1, maximumToleranceMeters: Double = 256) {
        self.initialToleranceMeters = initialToleranceMeters
        self.maximumToleranceMeters = maximumToleranceMeters
    }

    /// 折れ線の合計の点数を上限まで減らします。
    ///
    /// 責務: 各折れ線の端点を残し、合計の点数が pointBudget 以下になるまで許容誤差を倍々にし、上限でも超える時は等間隔に間引きます。
    /// - Parameters:
    ///   - polylines: 折れ線の列。
    ///   - requestedBudget: 合計の点数の上限。0 未満は 0 として扱い、各折れ線の端点だけを返します。
    /// - Returns: 減らした折れ線の列(本数と順序は入力と同じ)。
    func simplify(_ polylines: [[GeoCoordinate]], pointBudget requestedBudget: Int) -> [[GeoCoordinate]] {
        let pointBudget = max(requestedBudget, 0)
        guard Self.pointCount(of: polylines) > pointBudget else { return polylines }
        let significances = polylines.map(Self.significances(of:))
        var coarsest = polylines
        for tolerance in toleranceSteps() {
            coarsest = Self.retained(polylines, significances: significances, tolerance: tolerance)
            if Self.pointCount(of: coarsest) <= pointBudget { return coarsest }
        }
        return Self.decimated(coarsest, pointBudget: pointBudget)
    }

    /// 試す許容誤差の列を返します。
    ///
    /// 責務: 初期値から倍々にし、上限を超える手前で止め、最後に上限の値を足します。初期値か上限が正の有限値でなければ空です。
    /// - Returns: 昇順の許容誤差(m)。
    private func toleranceSteps() -> [Double] {
        guard initialToleranceMeters > 0, initialToleranceMeters.isFinite,
              maximumToleranceMeters >= initialToleranceMeters, maximumToleranceMeters.isFinite
        else { return [] }
        var steps: [Double] = []
        var tolerance = initialToleranceMeters
        while tolerance < maximumToleranceMeters, steps.count < Self.maximumToleranceSteps {
            steps.append(tolerance)
            tolerance *= 2
        }
        steps.append(maximumToleranceMeters)
        return steps
    }

    /// 折れ線の列の合計の点数を返します。
    ///
    /// 責務: 各折れ線の点数を足し合わせます。
    /// - Parameter polylines: 折れ線の列。
    /// - Returns: 合計の点数。
    private static func pointCount(of polylines: [[GeoCoordinate]]) -> Int {
        polylines.reduce(0) { $0 + $1.count }
    }

    /// 許容誤差で残す点だけの折れ線の列を返します。
    ///
    /// 責務: 各点の重要度が許容誤差より大きい点だけを、順序を保って残します。
    /// - Parameters:
    ///   - polylines: 元の折れ線の列。
    ///   - significances: 各折れ線の点ごとの重要度。
    ///   - tolerance: 許容誤差(m)。
    /// - Returns: 残した点の折れ線の列。
    private static func retained(_ polylines: [[GeoCoordinate]], significances: [[Double]], tolerance: Double) -> [[GeoCoordinate]] {
        zip(polylines, significances).map { polyline, significance in
            polyline.indices.filter { significance[$0] > tolerance }.map { polyline[$0] }
        }
    }

    /// 折れ線の各点の重要度を求めます。
    ///
    /// 責務: Douglas–Peucker の分割を1回だけ反復で行い、各点の「分割した時の距離」と祖先の距離の小さい方を重要度にします。
    /// 許容誤差 ε での Douglas–Peucker の結果は、重要度が ε より大きい点の集合と一致します。端点は無限大です。
    /// - Parameter polyline: 折れ線。
    /// - Returns: 点ごとの重要度(m)。
    private static func significances(of polyline: [GeoCoordinate]) -> [Double] {
        guard let origin = polyline.first else { return [] }
        let projection = GeoLocalProjection(origin: origin)
        let planar = polyline.map(projection.project)
        var significance = [Double](repeating: 0, count: planar.count)
        significance[0] = .infinity
        significance[planar.count - 1] = .infinity
        var pending: [(start: Int, end: Int, ceiling: Double)] = [(0, planar.count - 1, .infinity)]
        while let range = pending.popLast() {
            guard range.end - range.start >= 2 else { continue }
            let farthest = farthestPoint(in: planar, from: range.start, to: range.end)
            let value = min(farthest.distance, range.ceiling)
            significance[farthest.index] = value
            pending.append((range.start, farthest.index, value))
            pending.append((farthest.index, range.end, value))
        }
        return significance
    }

    /// 区間の両端を結ぶ線分から最も遠い内側の点を返します。
    ///
    /// 責務: start と end の間(両端を除く)の点から、線分までの距離が最大の点を選びます。
    /// 同じ距離なら区間の中央に近い点を選び、ジグザグのような同じ距離の続く入力で分割が偏らない(二乗の時間にならない)ようにします。
    /// - Parameters:
    ///   - planar: 平面へ投影した点の列。
    ///   - start: 区間の始点の位置。
    ///   - end: 区間の終点の位置(start + 2 以上)。
    /// - Returns: 最も遠い点の位置と距離(m)。
    private static func farthestPoint(in planar: [GeoPlanarPoint], from start: Int, to end: Int) -> (index: Int, distance: Double) {
        let middle = start + (end - start) / 2
        var best = (index: start + 1, distance: -Double.infinity)
        for index in (start + 1)..<end {
            let distance = distanceToSegment(planar[index], planar[start], planar[end])
            let isCloserTie = distance == best.distance && abs(index - middle) < abs(best.index - middle)
            if distance > best.distance || isCloserTie { best = (index, distance) }
        }
        return best
    }

    /// 点から線分までの距離を返します。
    ///
    /// 責務: 点を線分へ射影した位置を 0...1 に切り詰め、そこからの距離を求めます。両端が同じなら端点までの距離です。
    /// - Parameters:
    ///   - point: 点。
    ///   - a: 線分の始点。
    ///   - b: 線分の終点。
    /// - Returns: 距離(m)。
    private static func distanceToSegment(_ point: GeoPlanarPoint, _ a: GeoPlanarPoint, _ b: GeoPlanarPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let ratio = lengthSquared > 0 ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1) : 0
        let offsetX = point.x - (a.x + ratio * dx)
        let offsetY = point.y - (a.y + ratio * dy)
        return (offsetX * offsetX + offsetY * offsetY).squareRoot()
    }

    /// 折れ線の列を、端点を残して等間隔に間引きます。
    ///
    /// 責務: 端点の数を除いた残りの上限を、各折れ線の内側の点数に比例して(切り捨てで)配り、それぞれ等間隔に選びます。
    /// - Parameters:
    ///   - polylines: 間引く折れ線の列。
    ///   - pointBudget: 合計の点数の上限。
    /// - Returns: 間引いた折れ線の列。
    private static func decimated(_ polylines: [[GeoCoordinate]], pointBudget: Int) -> [[GeoCoordinate]] {
        let endpointCount = polylines.reduce(0) { $0 + min($1.count, 2) }
        let interiorCount = polylines.reduce(0) { $0 + max($1.count - 2, 0) }
        let spare = max(pointBudget - endpointCount, 0)
        return polylines.map { polyline in
            let interior = max(polyline.count - 2, 0)
            let share = interiorCount > 0 ? spare * interior / interiorCount : 0
            return evenlySpaced(polyline, interiorPointCount: min(share, interior))
        }
    }

    /// 1本の折れ線から、端点と等間隔の内側の点を選びます。
    ///
    /// 責務: 始点と終点に加え、j·(n−1)/(k+1)(j = 1...k、四捨五入)の位置の点を順に選びます。2点以下ならそのままです。
    /// - Parameters:
    ///   - polyline: 折れ線。
    ///   - interiorPointCount: 残す内側の点の数 k(0...n−2)。
    /// - Returns: 選んだ点の折れ線。
    private static func evenlySpaced(_ polyline: [GeoCoordinate], interiorPointCount: Int) -> [GeoCoordinate] {
        guard polyline.count > 2 else { return polyline }
        let lastIndex = polyline.count - 1
        let divisor = interiorPointCount + 1
        let interior = (0..<interiorPointCount).map { offset in
            polyline[((offset + 1) * lastIndex * 2 + divisor) / (divisor * 2)]
        }
        return [polyline[0]] + interior + [polyline[lastIndex]]
    }
}
