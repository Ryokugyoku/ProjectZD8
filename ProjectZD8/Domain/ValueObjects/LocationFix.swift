import Foundation

/// 1点の位置観測です。接続セッションに依存せず、記録と将来の案内で共有します。
nonisolated struct LocationFix: Equatable, Sendable {
    /// 緯度(度)。-90...90。
    let latitude: Double
    /// 経度(度)。-180...180。
    let longitude: Double
    /// 標高(メートル)。取得できない場合は `nil`。垂直精度と同時に値を持ちます。
    let altitudeMeters: Double?
    /// 水平精度(メートル)。有限かつ 0 以上。
    let horizontalAccuracyMeters: Double
    /// 垂直精度(メートル)。標高と同時に値を持ち、0 以上。
    let verticalAccuracyMeters: Double?
    /// 対地速度(メートル毎秒)。0 以上。取得できない場合は `nil`。
    let speedMetersPerSecond: Double?
    /// 進行方向(度)。0 以上 360 未満。取得できない場合は `nil`。
    let courseDegrees: Double?
    /// 位置が観測された実時間。
    let observedAt: Date
    /// 位置が観測された時点の単調時計(ナノ秒)。
    let monotonicNanoseconds: UInt64

    /// 不変条件を満たす場合だけ位置を作ります。
    ///
    /// 責務: 緯度経度・精度・標高と垂直精度の組・速度・進行方向の範囲を検証し、満たさなければ `nil` を返します。
    /// NaN と無限大は不正として扱います。
    /// - Parameters:
    ///   - latitude: 緯度(度)。
    ///   - longitude: 経度(度)。
    ///   - altitudeMeters: 標高(メートル)。
    ///   - horizontalAccuracyMeters: 水平精度(メートル)。
    ///   - verticalAccuracyMeters: 垂直精度(メートル)。
    ///   - speedMetersPerSecond: 対地速度(メートル毎秒)。
    ///   - courseDegrees: 進行方向(度)。
    ///   - observedAt: 観測された実時間。
    ///   - monotonicNanoseconds: 観測時点の単調時計(ナノ秒)。
    init?(
        latitude: Double,
        longitude: Double,
        altitudeMeters: Double?,
        horizontalAccuracyMeters: Double,
        verticalAccuracyMeters: Double?,
        speedMetersPerSecond: Double?,
        courseDegrees: Double?,
        observedAt: Date,
        monotonicNanoseconds: UInt64
    ) {
        guard Self.isValidCoordinate(latitude: latitude, longitude: longitude),
              Self.isValidAccuracy(horizontalAccuracyMeters),
              Self.isValidVerticalPair(altitude: altitudeMeters, accuracy: verticalAccuracyMeters),
              Self.isValidOptional(speedMetersPerSecond, in: 0..<Double.infinity),
              Self.isValidOptional(courseDegrees, in: 0..<360)
        else { return nil }
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeMeters = altitudeMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.courseDegrees = courseDegrees
        self.observedAt = observedAt
        self.monotonicNanoseconds = monotonicNanoseconds
    }

    /// 緯度経度が範囲内の有限値かを返します。
    ///
    /// 責務: 緯度 -90...90 と経度 -180...180 を判定します。
    private static func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        (-90.0...90.0).contains(latitude) && (-180.0...180.0).contains(longitude)
    }

    /// 精度が有限かつ 0 以上かを返します。
    ///
    /// 責務: 精度値 1 つの妥当性を判定します。
    private static func isValidAccuracy(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }

    /// 標高と垂直精度の組が妥当かを返します。
    ///
    /// 責務: 両方 nil、または標高が有限で垂直精度が妥当な組だけを許可します。
    private static func isValidVerticalPair(altitude: Double?, accuracy: Double?) -> Bool {
        switch (altitude, accuracy) {
        case (nil, nil):
            return true
        case let (altitude?, accuracy?):
            return altitude.isFinite && isValidAccuracy(accuracy)
        default:
            return false
        }
    }

    /// 任意値が nil か、範囲内の有限値かを返します。
    ///
    /// 責務: 速度や進行方向のような任意の値を範囲で判定します。
    private static func isValidOptional(_ value: Double?, in range: Range<Double>) -> Bool {
        guard let value else { return true }
        return value.isFinite && range.contains(value)
    }
}
