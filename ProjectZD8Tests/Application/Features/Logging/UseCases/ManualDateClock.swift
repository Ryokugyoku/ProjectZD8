import Foundation

/// テストが任意の日時に設定できる手動の実時刻clockです。
final class ManualDateClock: @unchecked Sendable {
    /// 現在値を保護するロックです。
    private let lock = NSLock()
    /// ロックで保護した現在の日時です。
    private var current: Date

    /// 初期日時を指定して生成します。
    ///
    /// 責務: 指定した日時を返す手動clockを構築します。
    /// - Parameter initial: 最初に返す日時。
    init(_ initial: Date) {
        current = initial
    }

    /// 現在の日時を返します。
    ///
    /// 責務: ロック下で現在の日時を1回読み取ります。
    /// - Returns: 設定済みの日時。
    func now() -> Date {
        lock.withLock { current }
    }

    /// 現在の日時を設定します。
    ///
    /// 責務: 次に返す日時を置き換えます。
    /// - Parameter date: 設定する日時。
    func set(_ date: Date) {
        lock.withLock { current = date }
    }
}
