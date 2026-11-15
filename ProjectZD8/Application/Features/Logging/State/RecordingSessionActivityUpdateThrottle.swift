import Foundation

/// 記録中表示の更新をシステムへ送る頻度を抑える間引きです。時刻は引数で受け取ります。
///
/// 規則: 初回は送る。状態キーが前回送信と違えば間隔を待たず送る。内容が前回送信と同じなら送らない。
/// それ以外は前回送信から `minimumInterval` 以上(ちょうどを含む)経っていれば送る。
nonisolated struct RecordingSessionActivityUpdateThrottle: Equatable, Sendable {
    /// 状態キーが変わらない更新の最短間隔(秒)です。
    static let minimumInterval: TimeInterval = 3

    /// 前回送った内容です。まだ送っていなければ `nil` です。
    private(set) var lastSentContent: RecordingSessionActivityContent?
    /// 前回送った時刻です。まだ送っていなければ `nil` です。
    private(set) var lastSentAt: Date?

    /// 送信前の間引き状態を生成します。
    ///
    /// 責務: 前回送信なしの状態から始めます。
    init() {}

    /// 内容を今送るべきか判定し、送るなら送信済みとして記録します。
    ///
    /// 責務: 1件の内容と時刻を送る/送らないへ変換し、送る場合は前回送信を更新します。
    /// - Parameters:
    ///   - content: 送ろうとしている内容。
    ///   - now: 現在時刻。
    /// - Returns: 送るべきなら `true`。
    mutating func admit(_ content: RecordingSessionActivityContent, at now: Date) -> Bool {
        guard shouldSend(content, at: now) else { return false }
        lastSentContent = content
        lastSentAt = now
        return true
    }

    /// 内容を今送るべきかを判定します。状態は変えません。
    ///
    /// 責務: 前回送信との差と経過時間から送信可否を決めます。
    /// - Parameters:
    ///   - content: 送ろうとしている内容。
    ///   - now: 現在時刻。
    /// - Returns: 送るべきなら `true`。
    func shouldSend(_ content: RecordingSessionActivityContent, at now: Date) -> Bool {
        guard let lastSentContent, let lastSentAt else { return true }
        if content.statusKey != lastSentContent.statusKey { return true }
        if content == lastSentContent { return false }
        return now.timeIntervalSince(lastSentAt) >= Self.minimumInterval
    }
}
