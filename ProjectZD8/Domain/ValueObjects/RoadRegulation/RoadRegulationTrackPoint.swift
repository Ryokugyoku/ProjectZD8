import Foundation

/// 突き合わせに使う軌跡の1点です。
nonisolated struct RoadRegulationTrackPoint: Equatable, Sendable {
    /// 位置サンプルの連番。
    let sequence: Int64
    /// 選んだ時刻軸の秒。
    let time: TimeInterval
    /// 実時間(時間帯・曜日の条件に使う)。
    let observedAt: Date
    /// 座標。
    let coordinate: GeoCoordinate
    /// 水平精度(m)。
    let horizontalAccuracyMeters: Double
    /// 進行方向(度、北0・時計回り)。無ければ `nil`。
    let courseDegrees: Double?
    /// GPS の速さ(m/s)。無ければ `nil`。
    let gpsSpeedMetersPerSecond: Double?
}
