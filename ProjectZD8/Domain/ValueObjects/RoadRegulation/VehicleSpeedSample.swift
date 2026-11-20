import Foundation

/// 時刻軸の上の車速1点です。
nonisolated struct VehicleSpeedSample: Equatable, Sendable {
    /// 選んだ時刻軸の秒。
    let time: TimeInterval
    /// 車速(km/h)。
    let kph: Double
}
