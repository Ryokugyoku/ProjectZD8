import Foundation

/// 時間軸へ重ねる整備記録のマーカーです。
nonisolated struct AnalysisMaintenanceMarker: Codable, Equatable, Sendable {
    let id: String
    let date: Date
    let title: String
    /// `light` または `heavy` です。
    let kind: String
    let odometerKilometers: Double?
}
