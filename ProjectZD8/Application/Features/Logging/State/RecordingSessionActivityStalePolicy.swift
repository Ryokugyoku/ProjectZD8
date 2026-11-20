import Foundation

/// 記録中の常時表示が、更新の途絶えた後に「古い」扱いになる時刻の規則です。
///
/// アプリが背面で止められて更新が届かなくなっても、有効期限を過ぎた表示はシステムが古いと判定し、
/// 表示側が「更新が止まっています」と出せるようにします。
nonisolated enum RecordingSessionActivityStalePolicy {
    /// 開始・更新を受け付けてから古い扱いになるまでの時間(秒)です。60秒です。
    static let staleInterval: TimeInterval = 60

    /// 開始・更新を受け付けた時刻から有効期限を求めます。
    ///
    /// 責務: 受け付けた時刻に有効期限までの時間を足します。
    /// - Parameter updatedAt: 開始・更新を受け付けた時刻。
    /// - Returns: 表示が古い扱いになる時刻。
    static func staleDate(updatedAt: Date) -> Date {
        updatedAt.addingTimeInterval(staleInterval)
    }
}
