import Foundation

/// `RecordingSessionActivityAttributes` の入れ子の値型 `EndedSummary` です。ActivityKit に依存せず、アプリ・Extension・macOS の単体テストで共有します。
extension RecordingSessionActivityAttributes {
    /// 記録終了後の表示に載せる、走行時間(固定値)と各種の最大値です。
    nonisolated struct EndedSummary: Codable, Hashable, Sendable {
        /// 開始から終了までの走行時間(秒)です。
        var drivingSeconds: TimeInterval
        /// 車速(km/h)の最大値です。
        var maximumVehicleSpeed: Metric
        /// エンジン回転数(rpm)の最大値です。
        var maximumEngineSpeed: Metric
        /// スロットル開度(%)の最大値です。
        var maximumThrottlePosition: Metric
    }
}
