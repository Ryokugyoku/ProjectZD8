import Foundation

/// 長期傾向の1セッション分の集計です。
nonisolated struct VehicleTrendSession: Codable, Equatable, Sendable {
    let id: String
    let startedAt: Date
    let durationSeconds: Double
    let distanceKilometers: Double?
    let odometerStartKilometers: Double?
    let isDemo: Bool
    let sampleCount: Int
    let stats: [VehicleTrendStat]
}
