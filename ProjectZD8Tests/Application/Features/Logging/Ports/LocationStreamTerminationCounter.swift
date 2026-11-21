import Foundation

/// 位置の流れの終了(`onTermination`)を、呼ばれたスレッドに関係なく同期的に数える計数器です。
nonisolated final class LocationStreamTerminationCounter: @unchecked Sendable {
    /// 回数を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した終了回数です。
    private var storedCount = 0

    /// 0 回の計数器を生成します。
    ///
    /// 責務: 終了を1回も数えていない状態を構築します。
    init() {}

    /// これまでに数えた終了回数です。
    var count: Int {
        lock.withLock { storedCount }
    }

    /// 終了を1回数えます。
    ///
    /// 責務: ロックの中で終了回数を1つ増やします。
    func increment() {
        lock.withLock { storedCount += 1 }
    }
}
