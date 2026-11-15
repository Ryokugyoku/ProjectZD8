import Foundation

/// 別Taskで実行した期限待ちが終わったかどうかと、その失敗を記録する入れ物です。
final class DeadlineWaiterCompletionFlag: @unchecked Sendable {
    /// 状態を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した、終わったかどうかです。
    private var storedIsFinished = false
    /// ロックで保護した失敗です。
    private var storedError: (any Error)?

    /// 終わっていない状態で生成します。
    ///
    /// 責務: 未完了の入れ物を構築します。
    init() {}

    /// 終わったかどうかです。
    var isFinished: Bool {
        lock.withLock { storedIsFinished }
    }

    /// 期限待ちの失敗です。成功した場合と未完了の場合は `nil` です。
    var error: (any Error)? {
        lock.withLock { storedError }
    }

    /// 終わったことを記録します。
    ///
    /// 責務: 完了と、失敗した場合はそのエラーを保存します。
    /// - Parameter error: 期限待ちの失敗。成功なら `nil`。
    func finish(with error: (any Error)?) {
        lock.withLock {
            storedIsFinished = true
            storedError = error
        }
    }
}
