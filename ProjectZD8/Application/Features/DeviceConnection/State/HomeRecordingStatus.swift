import Foundation

/// ホームのセッション見出しに出す記録状態です。
nonisolated enum HomeRecordingStatus: Equatable, Sendable {
    /// 記録中です。開始時刻から経過時間を表示します。
    case recording(startedAt: Date)
    /// 記録していません。セッションを保存できなかった時などに「記録中」と偽らないための状態です。
    case notRecording

    /// 記録中を表すローカライズキーです。
    static let activeKey = "home.recording.active"
    /// 経過時間を読み上げるアクセシビリティ用のローカライズキーです。
    static let elapsedKey = "home.recording.elapsed"
    /// 記録していないことを表すローカライズキーです。
    static let notRecordingKey = "home.recording.not_recording"
}
