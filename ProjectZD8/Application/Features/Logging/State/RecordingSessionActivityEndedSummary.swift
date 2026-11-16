import Foundation

/// 記録終了後の表示に載せる、走行時間(固定値)と各種の最大値です。
nonisolated struct RecordingSessionActivityEndedSummary: Equatable, Codable, Sendable {
    /// 開始から終了までの走行時間(秒)です。0以上です。
    let drivingDuration: TimeInterval
    /// 項目ごとの最大値です。
    let maximums: RecordingSessionActivityMaximums

    /// 開始・終了時刻と最大値から生成します。
    ///
    /// 責務: 走行時間を終了時刻から開始時刻を引いた固定値にし、負の値は0へ丸めます。
    /// - Parameters:
    ///   - startedAt: 記録を開始した時刻。
    ///   - endedAt: 記録が終わった時刻。
    ///   - maximums: 項目ごとの最大値。
    init(startedAt: Date, endedAt: Date, maximums: RecordingSessionActivityMaximums) {
        drivingDuration = max(0, endedAt.timeIntervalSince(startedAt))
        self.maximums = maximums
    }
}
