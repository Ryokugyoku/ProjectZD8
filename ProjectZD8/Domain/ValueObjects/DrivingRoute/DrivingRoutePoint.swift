import Foundation

/// 走行ルートの1点です。精度の検査を通った位置のサンプルを表します。
nonisolated struct DrivingRoutePoint: Equatable, Sendable {
    /// 元のサンプルのセッション内の連番です。
    let sequence: Int64
    /// 位置の座標です。
    let coordinate: GeoCoordinate
    /// 位置を観測した実時間です。
    let observedAt: Date
    /// 位置を観測した単調時刻(ナノ秒)です。
    let monotonicNanoseconds: UInt64
    /// 水平精度(m)です。
    let horizontalAccuracyMeters: Double
    /// 標高(海抜、m)です。無い時は `nil` です。
    let altitudeMeters: Double?
    /// 垂直精度(m)です。無い時は `nil` です。
    let verticalAccuracyMeters: Double?
}
