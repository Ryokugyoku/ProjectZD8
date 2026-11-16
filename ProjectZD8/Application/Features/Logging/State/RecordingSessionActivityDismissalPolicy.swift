import Foundation

/// 終了表示をロック画面へ残す時間と、自動で消す時刻の規則です。
nonisolated enum RecordingSessionActivityDismissalPolicy {
    /// 終了表示を残す時間(秒)です。5分です。
    static let retention: TimeInterval = 300

    /// 終了時刻から消去時刻を求めます。
    ///
    /// 責務: 終了時刻に保持時間を足します。
    /// - Parameter endedAt: 記録が終わった時刻。
    /// - Returns: 終了表示を消す時刻。
    static func dismissAt(endedAt: Date) -> Date {
        endedAt.addingTimeInterval(retention)
    }
}
