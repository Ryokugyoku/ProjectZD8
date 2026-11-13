import Foundation

/// 分析対象セッションの属性です。
nonisolated struct AnalysisSessionInfo: Codable, Equatable, Sendable {
    let id: String
    let vehicleId: String
    let startedAt: Date
    /// 終了済みなら記録時間、記録中なら最後のサンプル時刻(秒)です。
    let durationSeconds: Double
    let isRecording: Bool
    let isDemo: Bool
    let adapterName: String
    let platform: String
    let appVersion: String
    let endReason: String?
    let sampleCount: Int
    let respondedCount: Int
    let odometerStartKilometers: Double?
    let odometerEndKilometers: Double?
    /// 開始・終了の距離計から求めた走行距離です。求められなければ `nil` です。
    let distanceKilometers: Double?
}
