import CoreLocation
import Foundation

/// `CLLocation` を Domain の `LocationFix` へ変換します。判断は無効値の除外と単調時刻の補正だけです。
///
/// CoreLocation は無効な値を負の精度や負の値で表します。水平精度が無効な点は捨て、
/// それ以外の無効な値(標高と垂直精度・速度・進行方向)は点を残して `nil` にします。
nonisolated struct CoreLocationFixMapper: Sendable {
    /// 1秒あたりのナノ秒数です。
    private static let nanosecondsPerSecond: Double = 1_000_000_000

    /// 状態を持たない変換器を生成します。
    ///
    /// 責務: 変換器を構築します。
    init() {}

    /// 1点の `CLLocation` を `LocationFix` へ変換します。
    ///
    /// 責務: 無効な値を除外し、位置の古さを差し引いた単調時刻を付けて `LocationFix` を作ります。
    /// - Parameters:
    ///   - location: CoreLocation から受け取った位置。
    ///   - wallNow: 受信時の実時間。
    ///   - monotonicNow: 受信時の単調時計(ナノ秒)。
    /// - Returns: 変換した位置。水平精度が無効、または不変条件を満たさない場合は `nil`。
    func fix(from location: CLLocation, wallNow: Date, monotonicNow: UInt64) -> LocationFix? {
        guard location.horizontalAccuracy >= 0 else { return nil }
        let hasVertical = location.verticalAccuracy >= 0
        return LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitudeMeters: hasVertical ? location.altitude : nil,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            verticalAccuracyMeters: hasVertical ? location.verticalAccuracy : nil,
            speedMetersPerSecond: Self.speed(of: location),
            courseDegrees: Self.course(of: location),
            observedAt: location.timestamp,
            monotonicNanoseconds: Self.monotonicNanoseconds(
                observedAt: location.timestamp,
                wallNow: wallNow,
                monotonicNow: monotonicNow
            )
        )
    }

    /// 有効な速度を返します。
    ///
    /// 責務: 速度精度または速度が負、あるいは速度が有限でない場合に `nil` を返します。
    /// - Parameter location: 変換元の位置。
    /// - Returns: 速度(メートル毎秒)。無効なら `nil`。
    private static func speed(of location: CLLocation) -> Double? {
        guard location.speedAccuracy >= 0, location.speed >= 0, location.speed.isFinite else { return nil }
        return location.speed
    }

    /// 有効な進行方向を返します。
    ///
    /// 責務: 進行方向精度が負、または進行方向が 0 以上 360 未満でない場合に `nil` を返します。
    /// 360 以上を 0 へ丸めず `nil` にし、`LocationFix` の不変条件 0..<360 を満たします。
    /// - Parameter location: 変換元の位置。
    /// - Returns: 進行方向(度)。無効なら `nil`。
    private static func course(of location: CLLocation) -> Double? {
        guard location.courseAccuracy >= 0, (0..<360).contains(location.course) else { return nil }
        return location.course
    }

    /// 観測時点の単調時刻を求めます。
    ///
    /// 責務: 受信時の単調時計から位置の古さ(受信時の実時間 − 観測時刻、0 以上)を差し引きます。
    /// 差し引きが受信時の単調時計を超える場合は 0 に切り詰め、アンダーフローを起こしません。
    /// - Parameters:
    ///   - observedAt: 位置の観測時刻。
    ///   - wallNow: 受信時の実時間。
    ///   - monotonicNow: 受信時の単調時計(ナノ秒)。
    /// - Returns: 観測時点の単調時計(ナノ秒)。
    private static func monotonicNanoseconds(observedAt: Date, wallNow: Date, monotonicNow: UInt64) -> UInt64 {
        let ageNanoseconds = (max(0, wallNow.timeIntervalSince(observedAt)) * nanosecondsPerSecond).rounded()
        guard ageNanoseconds < Double(monotonicNow) else { return 0 }
        let (result, overflow) = monotonicNow.subtractingReportingOverflow(UInt64(ageNanoseconds))
        return overflow ? 0 : result
    }
}
