import Foundation

/// 検知待ち以外で届いた[記録開始]の選択(プロセス終了後に残った通知から起動した場合など)を、有効期限つきで保持した「記録開始の意思」です。
nonisolated struct AdapterLinkRecordingIntent: Equatable, Sendable {
    /// 選択を受け取った時刻です(監視の時計。単調時計基準)。
    let selectedAt: Date

    /// 選択を受け取った時刻を固定して生成します。
    ///
    /// 責務: 有効期限の起点を1件の不変値へまとめます。
    /// - Parameter selectedAt: 選択を受け取った時刻。
    init(selectedAt: Date) {
        self.selectedAt = selectedAt
    }
}
