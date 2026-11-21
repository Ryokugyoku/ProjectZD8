import Foundation

/// Raw ログから取り出した車速1点(時刻の軸を選ぶ前)です。
nonisolated struct VehicleSpeedRawObservation: Equatable, Sendable {
    /// 実時間。
    let observedAt: Date
    /// 単調時計の時刻(ナノ秒)。旧い記録では `nil`。
    let monotonicNanoseconds: UInt64?
    /// 車速(km/h)。
    let kph: Double
}
