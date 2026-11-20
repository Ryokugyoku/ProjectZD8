import Foundation

/// 緯度・経度の範囲で表した外接矩形です。常に min <= max で、各値は座標として有効な範囲に収まります。
nonisolated struct GeoBoundingBox: Equatable, Sendable {
    /// 緯度1度あたりのメートル数(平均地球半径 6,371,008.8 m × π / 180)です。
    static let metersPerDegree = 111_195.08

    /// 南端の緯度(度)。
    let minLatitude: Double
    /// 北端の緯度(度)。
    let maxLatitude: Double
    /// 西端の経度(度)。
    let minLongitude: Double
    /// 東端の経度(度)。
    let maxLongitude: Double

    /// 4辺を検査して外接矩形を作ります。
    ///
    /// 責務: 各値が座標として有効で、min <= max である範囲だけを受け入れます。
    /// - Parameters:
    ///   - minLatitude: 南端の緯度。
    ///   - maxLatitude: 北端の緯度。
    ///   - minLongitude: 西端の経度。
    ///   - maxLongitude: 東端の経度。
    /// - Returns: 値が無効、または min > max なら `nil`。
    init?(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        guard Self.isValidRange(min: minLatitude, max: maxLatitude, isValid: GeoCoordinate.isValidLatitude),
              Self.isValidRange(min: minLongitude, max: maxLongitude, isValid: GeoCoordinate.isValidLongitude)
        else { return nil }
        self.init(checkedMinLatitude: minLatitude, maxLatitude: maxLatitude, minLongitude: minLongitude, maxLongitude: maxLongitude)
    }

    /// 座標の列をすべて含む最小の外接矩形を作ります。
    ///
    /// 責務: 座標の緯度・経度の最小値と最大値から範囲を決めます。
    /// - Parameter coordinates: 含める座標。
    /// - Returns: 座標が空なら `nil`。
    init?(enclosing coordinates: [GeoCoordinate]) {
        guard let first = coordinates.first else { return nil }
        var box = GeoBoundingBox(point: first)
        for coordinate in coordinates.dropFirst() {
            box = box.union(GeoBoundingBox(point: coordinate))
        }
        self = box
    }

    /// 1点だけを含む外接矩形を作ります。
    ///
    /// 責務: 有効な座標から幅0の範囲を作ります。
    /// - Parameter point: 含める座標。
    private init(point: GeoCoordinate) {
        self.init(
            checkedMinLatitude: point.latitude,
            maxLatitude: point.latitude,
            minLongitude: point.longitude,
            maxLongitude: point.longitude
        )
    }

    /// 検査済みの4辺から外接矩形を作ります。
    ///
    /// 責務: 呼び出し元が有効性を保証した値をそのまま保持します。
    /// - Parameters:
    ///   - checkedMinLatitude: 南端の緯度。
    ///   - maxLatitude: 北端の緯度。
    ///   - minLongitude: 西端の経度。
    ///   - maxLongitude: 東端の経度。
    private init(checkedMinLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = checkedMinLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }

    /// 座標が範囲に含まれるかを返します。
    ///
    /// 責務: 境界上の点を含めて内外を判定します。
    /// - Parameter coordinate: 調べる座標。
    /// - Returns: 境界を含めて範囲内なら `true`。
    func contains(_ coordinate: GeoCoordinate) -> Bool {
        (minLatitude...maxLatitude).contains(coordinate.latitude)
            && (minLongitude...maxLongitude).contains(coordinate.longitude)
    }

    /// 2つの範囲をともに含む最小の外接矩形を返します。
    ///
    /// 責務: 4辺それぞれの外側の値を選びます。
    /// - Parameter other: 合わせる範囲。
    /// - Returns: 両方を含む外接矩形。
    func union(_ other: GeoBoundingBox) -> GeoBoundingBox {
        GeoBoundingBox(
            checkedMinLatitude: Swift.min(minLatitude, other.minLatitude),
            maxLatitude: Swift.max(maxLatitude, other.maxLatitude),
            minLongitude: Swift.min(minLongitude, other.minLongitude),
            maxLongitude: Swift.max(maxLongitude, other.maxLongitude)
        )
    }

    /// 四方へメートル単位で広げた外接矩形を返します。
    ///
    /// 責務: 緯度は meters / k、経度は meters / (k·cos(max|緯度|)) だけ広げ、有効な範囲で切り詰めます。
    /// - Parameter meters: 広げる距離(m)。負の値と有限でない値は 0 とみなします。
    /// - Returns: 広げた外接矩形。極付近で経度の幅が決まらない時は経度を全範囲にします。
    func expanded(byMeters meters: Double) -> GeoBoundingBox {
        let distance = meters.isFinite ? Swift.max(0, meters) : 0
        let latitudeDelta = distance / Self.metersPerDegree
        let longitudeDelta = Self.longitudeDelta(
            meters: distance,
            atLatitude: Swift.max(abs(minLatitude), abs(maxLatitude))
        )
        return GeoBoundingBox(
            checkedMinLatitude: Swift.max(-90, minLatitude - latitudeDelta),
            maxLatitude: Swift.min(90, maxLatitude + latitudeDelta),
            minLongitude: Swift.max(-180, minLongitude - longitudeDelta),
            maxLongitude: Swift.min(180, maxLongitude + longitudeDelta)
        )
    }

    /// 指定緯度で距離を経度の差へ直します。
    ///
    /// 責務: cos(緯度) が0に近く有限の値が得られない時は、全範囲を覆う差を返します。
    /// - Parameters:
    ///   - meters: 距離(m)。
    ///   - latitude: 基準の緯度(度)。
    /// - Returns: 経度の差(度)。
    private static func longitudeDelta(meters: Double, atLatitude latitude: Double) -> Double {
        let delta = meters / (metersPerDegree * cos(latitude * Double.pi / 180))
        return delta.isFinite && delta >= 0 ? delta : 360
    }

    /// 1軸の範囲として有効かを返します。
    ///
    /// 責務: 両端が有効な値で、min <= max であることを判定します。
    /// - Parameters:
    ///   - min: 下端。
    ///   - max: 上端。
    ///   - isValid: 値の有効性の判定。
    /// - Returns: 有効なら `true`。
    private static func isValidRange(min: Double, max: Double, isValid: (Double) -> Bool) -> Bool {
        isValid(min) && isValid(max) && min <= max
    }
}
