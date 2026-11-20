import Foundation

/// 走行ルートの要約(長さ・記録できた時間・記録できた割合)です。
nonisolated struct DrivingRouteSummary: Equatable, Sendable {
    /// 区間内の隣り合う点の距離の和(m、区間をまたがない)です。
    let lengthMeters: Double
    /// 各区間の(最後の点 − 最初の点)の時間の和(秒)です。
    let recordedDuration: TimeInterval
    /// 記録できた時間 ÷ セッションの時間(0...1)です。分母が0以下なら `nil` です。
    let coverageRatio: Double?
}
