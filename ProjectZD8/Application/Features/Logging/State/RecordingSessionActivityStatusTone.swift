/// 記録中表示の状態欄の強調です。
nonisolated enum RecordingSessionActivityStatusTone: Equatable, Codable, Sendable {
    /// 通常の状態です(アクセント色のシアンで描きます)。
    case normal
    /// 取得が途切れた・失敗したなど注意が要る状態です(警告色のオレンジで描きます)。
    case warning
}
